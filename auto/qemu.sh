#!/bin/bash
#
# Cross-build ST for one Linux CPU, and run the utest and the tools with qemu-user.
#
#   ./auto/qemu.sh <cpu> [utest|tools|tools-malloc|all]
#
# CPUs: x86_64, aarch64, i386, arm, riscv64, loongarch64, mips, mipsel, mips64, mips64el.
# The second argument picks what to run, all by default:
#   utest         st_utest
#   tools         auto/tools.sh
#   tools-malloc  auto/tools.sh with EXTRA_CFLAGS=-DMALLOC_STACK
#   all           all three, in that order, and every one runs even when another fails
#
# On the host, it builds the Docker image from auto/qemu/Dockerfile when missing, and runs itself in it with the
# checkout mounted. The image is local only, never pushed to a registry. Its tag, st-qemu:<hash>, is a short hash
# of every file in auto/qemu/, so a change there, even a comment, builds a new image. Old images are kept; after
# a build, the script prints the docker rmi command for the older st-qemu tags.
#
# In the container, it exports the cross toolchain, CC, CXX, AR, LD and RANLIB, which the Makefiles take from
# the environment, and builds in place in LINUX_<cpu>_qemu_DBG, so the CPUs and the native Linux build never
# share objects. A CPU that is the container's own runs natively; any other runs with qemu-<cpu> -L <sysroot>,
# which auto/tools.sh takes from ST_TOOL_RUN.
#
# It prints one line per run, "RESULT <cpu> <run> PASS|FAIL (<seconds>s)", with the log of a failed run
# before it, and exits 1 when any run failed. A run that leaves out what qemu-user cannot run on that CPU prints
# "SKIP <cpu> <run> <what>: <why>" before its RESULT line.
#
# Examples:
#   ./auto/qemu.sh riscv64
#   ./auto/qemu.sh mips utest

cd "$(dirname "$0")/.." || exit 1

CPU=$1
WHAT=${2:-all}

# The GNU triple, the compiler suffix, the qemu-user CPU, and the uname -m of each CPU.
SUFFIX=
case $CPU in
    x86_64)      TRIPLE=x86_64-linux-gnu;        QEMU=x86_64;      MACHINE=x86_64 ;;
    aarch64)     TRIPLE=aarch64-linux-gnu;       QEMU=aarch64;     MACHINE=aarch64 ;;
    i386)        TRIPLE=i686-linux-gnu;          QEMU=i386;        MACHINE=i386 ;;
    arm)         TRIPLE=arm-linux-gnueabihf;     QEMU=arm;         MACHINE=armv7l ;;
    riscv64)     TRIPLE=riscv64-linux-gnu;       QEMU=riscv64;     MACHINE=riscv64 ;;
    loongarch64) TRIPLE=loongarch64-linux-gnu;   QEMU=loongarch64; MACHINE=loongarch64; SUFFIX=-14 ;;
    mips)        TRIPLE=mips-linux-gnu;          QEMU=mips;        MACHINE=mips ;;
    mipsel)      TRIPLE=mipsel-linux-gnu;        QEMU=mipsel;      MACHINE=mipsel ;;
    mips64)      TRIPLE=mips64-linux-gnuabi64;   QEMU=mips64;      MACHINE=mips64 ;;
    mips64el)    TRIPLE=mips64el-linux-gnuabi64; QEMU=mips64el;    MACHINE=mips64el ;;
    *)
        echo "Usage: $0 <cpu> [utest|tools|tools-malloc|all]" >&2
        echo "CPUs: x86_64 aarch64 i386 arm riscv64 loongarch64 mips mipsel mips64 mips64el" >&2
        exit 2
        ;;
esac
case $WHAT in
    utest|tools|tools-malloc) RUNS=$WHAT ;;
    all) RUNS="utest tools tools-malloc" ;;
    *) echo "Usage: $0 <cpu> [utest|tools|tools-malloc|all]" >&2; exit 2 ;;
esac

# On the host: run this script in the image.
if [[ -z $ST_QEMU_CONTAINER ]]; then
    # The tag is a short hash of the path and content of every file in the build context, auto/qemu/. git
    # hash-object reads the files as they are on disk, so uncommitted edits count too.
    HASH=$(cd auto/qemu && for f in $(find . -type f | LC_ALL=C sort); do echo "$f $(git hash-object "$f")"; done |
        git hash-object --stdin | cut -c1-12)
    if [[ -z $HASH ]]; then
        echo "Failed to hash auto/qemu/" >&2
        exit 1
    fi
    IMAGE=st-qemu:$HASH
    if ! docker image inspect $IMAGE >/dev/null 2>&1; then
        echo "Build the image $IMAGE"
        docker build -t $IMAGE auto/qemu || exit 1
        OLD=$(docker image ls st-qemu --format "{{.Repository}}:{{.Tag}}" | grep -v "^st-qemu:$HASH" | grep -v "<none>")
        if [[ -n $OLD ]]; then
            echo "Older images are kept, about 3 GB each. To remove them:"
            echo "  docker rmi" $OLD
        fi
    fi
    exec docker run --rm -e ST_QEMU_CONTAINER=1 --user "$(id -u):$(id -g)" \
        -v "$(pwd)":/st -w /st $IMAGE bash auto/qemu.sh "$CPU" "$WHAT"
fi

export CC=$TRIPLE-gcc$SUFFIX CXX=$TRIPLE-g++$SUFFIX AR=$TRIPLE-ar LD=$TRIPLE-ld RANLIB=$TRIPLE-ranlib
export TARGETDIR=LINUX_${CPU}_qemu_DBG
ST_TOOL_RUN=
if [[ $(uname -m) != "$MACHINE" ]]; then
    ST_TOOL_RUN="qemu-$QEMU -L /usr/$TRIPLE"
fi
export ST_TOOL_RUN

# What qemu-user itself cannot run on a CPU, though ST is fine: a gtest filter and the tools to leave out, with
# the reason. Each skip prints a SKIP line. Known ST failures are never listed here; they stay visible.
UTEST_FILTER=
SKIP_TOOLS=
SKIP_WHY=
if [[ -n $ST_TOOL_RUN ]]; then
    case $CPU in
        x86_64)
            # qemu-x86_64 8.2.2 crashes, "QEMU internal SIGSEGV", in pthread_getattr_np on the main thread, also in
            # a program without ST. The primordial stack test and the lifecycle tool call it.
            UTEST_FILTER=-PrimordialStackTest.DescribesTheMainThreadStack
            SKIP_TOOLS=lifecycle
            SKIP_WHY="qemu-x86_64 crashes in pthread_getattr_np on the main thread"
            ;;
    esac
fi

# The tools to run, every folder in tools/ but SKIP_TOOLS.
TOOLS=
for dir in tools/*/; do
    name=$(basename "$dir")
    if [[ " $SKIP_TOOLS " != *" $name "* ]]; then
        TOOLS="$TOOLS $name"
    fi
done

# Build the library with EXTRA_CFLAGS $1, then the utest, and run it. -B rebuilds the library, so it never
# keeps objects built with other flags; the utest objects depend on the library and follow it.
run_utest() {
    make -B linux-debug EXTRA_CFLAGS="$1" || return 1
    make -C utest EXTRA_CFLAGS="$1" || return 1
    $ST_TOOL_RUN ./obj/st_utest ${UTEST_FILTER:+--gtest_filter=$UTEST_FILTER}
}

LOG=/tmp/st-qemu.log
FAILED=0
for run in $RUNS; do
    start=$(date +%s)
    status=PASS
    case $run in
        utest) run_utest "" > $LOG 2>&1 || status=FAIL ;;
        tools) ./auto/tools.sh $TOOLS > $LOG 2>&1 || status=FAIL ;;
        tools-malloc) EXTRA_CFLAGS=-DMALLOC_STACK ./auto/tools.sh $TOOLS > $LOG 2>&1 || status=FAIL ;;
    esac
    if [[ $status == FAIL ]]; then
        tail -40 $LOG | sed 's/^/  | /'
        FAILED=1
    fi
    if [[ $run == utest && -n $UTEST_FILTER ]]; then
        echo "SKIP $CPU $run ${UTEST_FILTER#-}: $SKIP_WHY"
    fi
    if [[ $run != utest && -n $SKIP_TOOLS ]]; then
        echo "SKIP $CPU $run $SKIP_TOOLS: $SKIP_WHY"
    fi
    echo "RESULT $CPU $run $status ($(( $(date +%s) - start ))s)"
done
rm -f /tmp/st-qemu.log
exit $FAILED
