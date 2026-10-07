#!/bin/bash
#
# Cross-build ST for one Linux CPU, or for every one at once, and run the utest and the tools with qemu-user.
#
#   ./auto/qemu.sh <cpu> [utest|tools|tools-malloc|asan|all]
#   ./auto/qemu.sh <cpu> shell [command]
#   ./auto/qemu.sh all [utest|tools|tools-malloc|asan|all]
#
# CPUs: x86_64, aarch64, i386, arm, riscv64, loongarch64, mips, mipsel, mips64, mips64el.
# The second argument picks what to run, all by default:
#   utest         st_utest
#   tools         auto/tools.sh
#   tools-malloc  auto/tools.sh with EXTRA_CFLAGS=-DMALLOC_STACK
#   asan          st_utest and auto/tools.sh with ASAN and MALLOC_STACK, in LINUX_<cpu>_asan_DBG, only on a CPU
#                 that runs natively in its container; any other prints a SKIP line instead
#   all           all four, in that order, and every one runs even when another fails
#   shell         a bash in the image, with the toolchain and the variables below exported, to build, run and
#                 debug by hand; with a command, it runs that command instead, as bash -c
#
# On the host, it builds the Docker image from auto/qemu/Dockerfile when missing, and runs itself in it with the
# checkout mounted. The image is local only, never pushed to a registry. Its tag, st-qemu:<hash>, is a short hash
# of every file in auto/qemu/, so a change there, even a comment, builds a new image. Old images are kept; after
# a build, the script prints the docker rmi command for the older st-qemu tags.
#
# x86_64 on a Docker host of another CPU, such as Apple Silicon, runs in a second image, st-qemu:<hash>-amd64, the
# amd64 stage of the same Dockerfile, with --platform linux/amd64: Docker emulates the whole container, and the
# native g++ builds and runs x86_64 there, instead of qemu-x86_64, which crashes in pthread_getattr_np.
#
# In the container, it exports the toolchain, CC, CXX, AR, LD and RANLIB, which the Makefiles take from the
# environment, and TARGETDIR, LINUX_<cpu>_qemu_DBG. With TARGETDIR set, the Makefiles and auto/tools.sh build
# everything in place in that folder, the library, the utest and the tools, and leave the obj link alone. So the
# CPUs and the native Linux build never share objects, and two CPUs can run at once in one checkout. A CPU that
# is the container's own runs natively; any other runs with qemu-<cpu> -L <sysroot>, which auto/tools.sh takes
# from ST_TOOL_RUN.
#
# It prints one line per run, "RESULT <cpu> <run> PASS|FAIL (<seconds>s)", with the log of a failed run
# before it, and exits 1 when any run failed.
#
# With all instead of a CPU, it builds the images once, then runs every CPU at once, each in its own container
# and build folder, with its output in /tmp/st-qemu-all/<cpu>.log, kept until the next run. ST_QEMU_JOBS limits
# how many CPUs run at once, 5 by default: x86_64 in the emulated amd64 container takes the longest, and 5 at
# once finished as soon as 10. At the end it prints a summary, one row per CPU with PASS or FAIL and the seconds
# of each run, and the wall time, then the end of the log of each CPU that failed, and exits 1 when any CPU
# failed.
#
# Examples:
#   ./auto/qemu.sh riscv64
#   ./auto/qemu.sh mips utest
#   ./auto/qemu.sh x86_64 asan
#   ./auto/qemu.sh riscv64 shell
#   ./auto/qemu.sh all
#   ST_QEMU_JOBS=4 ./auto/qemu.sh all utest
#
# In the shell, the variables are those of the runs, CC, CXX, AR, LD, RANLIB, TARGETDIR and ST_TOOL_RUN, plus:
#   ST_QEMU_USER     the qemu-user binary of the CPU, such as qemu-riscv64
#   ST_QEMU_SYSROOT  the sysroot of the CPU, such as /usr/riscv64-linux-gnu
#
# To debug a CPU with gdb-multiarch, start the program under the gdb stub of qemu-user, which waits for gdb on a
# port, then attach gdb-multiarch to it, with the sysroot for the shared libraries. For example, stop the
# backtrace tool in the thread entry:
#   ./auto/qemu.sh riscv64 shell
#   make linux-debug && make -C tools/backtrace && cd $TARGETDIR/tools/backtrace
#   $ST_QEMU_USER -g 1234 -L $ST_QEMU_SYSROOT ./backtrace &
#   gdb-multiarch -ex "set sysroot $ST_QEMU_SYSROOT" -ex "target remote :1234" -ex "break _st_md_thread_start" \
#       -ex continue -ex bt ./backtrace
# It works on every CPU, aarch64 too. The shell of x86_64 always uses the cross image and qemu-x86_64, because
# gdb cannot trace a program in the container that Docker emulates for x86_64 on a host of another CPU.

cd "$(dirname "$0")/.." || exit 1

CPU=$1
WHAT=${2:-all}
CPUS="x86_64 aarch64 i386 arm riscv64 loongarch64 mips mipsel mips64 mips64el"

usage() {
    echo "Usage: $0 <cpu> [utest|tools|tools-malloc|asan|all]" >&2
    echo "       $0 <cpu> shell [command]" >&2
    echo "       $0 all [utest|tools|tools-malloc|asan|all]" >&2
    echo "CPUs: $CPUS" >&2
    exit 2
}

# The tag of the images, st-qemu:<hash>, is a short hash of the path and content of every file in the build
# context, auto/qemu/. git hash-object reads the files as they are on disk, so uncommitted edits count too.
image_hash() {
    HASH=$(cd auto/qemu && for f in $(find . -type f | LC_ALL=C sort); do echo "$f $(git hash-object "$f")"; done |
        git hash-object --stdin | cut -c1-12)
    if [[ -z $HASH ]]; then
        echo "Failed to hash auto/qemu/" >&2
        return 1
    fi
}

# Build the image $1 from the stage $2 of the Dockerfile, for the platform $3, when it is missing.
build_image() {
    if docker image inspect $1 >/dev/null 2>&1; then
        return 0
    fi
    echo "Build the image $1"
    docker build $3 --target $2 -t $1 auto/qemu || return 1
    OLD=$(docker image ls st-qemu --format "{{.Repository}}:{{.Tag}}" | grep -v "^st-qemu:$HASH" | grep -v "<none>")
    if [[ -n $OLD ]]; then
        echo "Older images are kept, about 3 GB each. To remove them:"
        echo "  docker rmi" $OLD
    fi
}

# Every CPU at once, on the host: build the images first, so the CPUs only use them, then run this script for
# each CPU in the background, at most ST_QEMU_JOBS at once, each with its own log. Then print a summary.
if [[ $CPU == all && -z $ST_QEMU_CONTAINER ]]; then
    case $WHAT in
        utest|tools|tools-malloc|asan) RUNS=$WHAT ;;
        all) RUNS="utest tools tools-malloc asan" ;;
        *) usage ;;
    esac
    image_hash || exit 1
    build_image st-qemu:$HASH cross "" || exit 1
    if [[ $(docker version --format '{{.Server.Arch}}') != amd64 ]]; then
        build_image st-qemu:$HASH-amd64 amd64 "--platform linux/amd64" || exit 1
    fi

    JOBS=${ST_QEMU_JOBS:-5}
    rm -rf /tmp/st-qemu-all
    mkdir -p /tmp/st-qemu-all || exit 1
    start=$(date +%s)
    for cpu in $CPUS; do
        while [[ $(jobs -pr | wc -l) -ge $JOBS ]]; do
            sleep 1
        done
        echo "Start $cpu, log /tmp/st-qemu-all/$cpu.log"
        (
            begin=$(date +%s)
            bash auto/qemu.sh $cpu $WHAT > /tmp/st-qemu-all/$cpu.log 2>&1 < /dev/null
            echo "EXIT $? $(( $(date +%s) - begin ))" >> /tmp/st-qemu-all/$cpu.log
        ) &
    done
    wait
    wall=$(( $(date +%s) - start ))

    # One row per CPU: PASS or FAIL, each run with its seconds or SKIP, and the seconds of the CPU.
    FAILED=
    total=0
    printf "\n%-12s %-6s" CPU RESULT
    for run in $RUNS; do
        printf " %-13s" $run
    done
    printf " %s\n" seconds
    for cpu in $CPUS; do
        log=/tmp/st-qemu-all/$cpu.log
        code=$(sed -n 's/^EXIT \([0-9]*\) [0-9]*$/\1/p' $log | tail -1)
        seconds=$(sed -n 's/^EXIT [0-9]* \([0-9]*\)$/\1/p' $log | tail -1)
        result=PASS
        if [[ $code != 0 ]]; then
            result=FAIL
            FAILED="$FAILED $cpu"
        fi
        total=$(( total + ${seconds:-0} ))
        printf "%-12s %-6s" $cpu $result
        for run in $RUNS; do
            cell=$(sed -n "s/^RESULT $cpu $run \([A-Z]*\) (\([0-9]*s\))$/\1 \2/p" $log | tail -1)
            if [[ -z $cell ]] && grep -q "^SKIP $cpu $run:" $log; then
                cell=SKIP
            fi
            printf " %-13s" "${cell:--}"
        done
        printf " %s\n" "${seconds:--}s"
    done
    echo "Wall time ${wall}s, at most $JOBS CPUs at once; the CPUs took ${total}s in all."

    for cpu in $FAILED; do
        echo
        echo "The end of the log of $cpu, /tmp/st-qemu-all/$cpu.log:"
        tail -40 /tmp/st-qemu-all/$cpu.log | sed 's/^/  | /'
    done
    if [[ -n $FAILED ]]; then
        echo
        echo "FAILED:$FAILED"
        exit 1
    fi
    exit 0
fi

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
    *) usage ;;
esac
case $WHAT in
    utest|tools|tools-malloc|asan) RUNS=$WHAT ;;
    all) RUNS="utest tools tools-malloc asan" ;;
    shell) RUNS= ;;
    *) usage ;;
esac

# On the host: run this script in the image.
if [[ -z $ST_QEMU_CONTAINER ]]; then
    image_hash || exit 1
    # The cross image runs on the CPU of the Docker host. x86_64 on another host CPU runs in the amd64 image,
    # except in the shell, which needs gdb and qemu-x86_64.
    IMAGE=st-qemu:$HASH
    TARGET=cross
    PLATFORM=
    if [[ $CPU == x86_64 && $WHAT != shell && $(docker version --format '{{.Server.Arch}}') != amd64 ]]; then
        IMAGE=st-qemu:$HASH-amd64
        TARGET=amd64
        PLATFORM="--platform linux/amd64"
    fi
    build_image $IMAGE $TARGET "$PLATFORM" || exit 1
    # The shell reads its input from the host, with a terminal when the host has one.
    TTY=
    if [[ $WHAT == shell ]]; then
        TTY=-i
        if [[ -t 0 && -t 1 ]]; then
            TTY=-it
        fi
    fi
    exec docker run --rm $TTY $PLATFORM -e ST_QEMU_CONTAINER=1 --user "$(id -u):$(id -g)" \
        -v "$(pwd)":/st -w /st $IMAGE bash auto/qemu.sh "$CPU" "$WHAT" "${@:3}"
fi

export CC=$TRIPLE-gcc$SUFFIX CXX=$TRIPLE-g++$SUFFIX AR=$TRIPLE-ar LD=$TRIPLE-ld RANLIB=$TRIPLE-ranlib
export TARGETDIR=LINUX_${CPU}_qemu_DBG
ST_TOOL_RUN=
if [[ $(uname -m) != "$MACHINE" ]]; then
    ST_TOOL_RUN="qemu-$QEMU -L /usr/$TRIPLE"
fi
export ST_TOOL_RUN

if [[ $WHAT == shell ]]; then
    export ST_QEMU_USER=qemu-$QEMU ST_QEMU_SYSROOT=/usr/$TRIPLE
    if [[ $# -gt 2 ]]; then
        exec bash -c "${*:3}"
    fi
    echo "ST for $CPU: CC=$CC TARGETDIR=$TARGETDIR ST_TOOL_RUN=$ST_TOOL_RUN"
    exec bash
fi

# Build the library with EXTRA_CFLAGS $1, then the utest, and run it. -B rebuilds the library, so it never
# keeps objects built with other flags; the utest objects depend on the library and follow it.
run_utest() {
    make -B linux-debug EXTRA_CFLAGS="$1" || return 1
    make -C utest EXTRA_CFLAGS="$1" || return 1
    $ST_TOOL_RUN ./$TARGETDIR/st_utest
}

# The utest and the tools with ASAN, in their own build folder, because the gtest objects do not follow the
# flags. An ASAN report fails the run.
run_asan() (
    flags="-DMALLOC_STACK -DMD_ASAN -fsanitize=address -fno-omit-frame-pointer"
    export TARGETDIR=LINUX_${CPU}_asan_DBG
    make -B linux-debug EXTRA_CFLAGS="$flags" || exit 1
    make -C utest EXTRA_CFLAGS="$flags" UTEST_FLAGS=-fsanitize=address || exit 1
    ./$TARGETDIR/st_utest || exit 1
    EXTRA_CFLAGS="$flags" LDFLAGS=-fsanitize=address ./auto/tools.sh
)

LOG=/tmp/st-qemu.log
FAILED=0
for run in $RUNS; do
    if [[ $run == asan && -n $ST_TOOL_RUN ]]; then
        echo "SKIP $CPU $run: ASAN runs only natively, not under qemu-user"
        continue
    fi
    start=$(date +%s)
    status=PASS
    case $run in
        utest) run_utest "" > $LOG 2>&1 || status=FAIL ;;
        tools) ./auto/tools.sh > $LOG 2>&1 || status=FAIL ;;
        tools-malloc) EXTRA_CFLAGS=-DMALLOC_STACK ./auto/tools.sh > $LOG 2>&1 || status=FAIL ;;
        asan) run_asan > $LOG 2>&1 || status=FAIL ;;
    esac
    if [[ $status == FAIL ]]; then
        tail -40 $LOG | sed 's/^/  | /'
        FAILED=1
    fi
    echo "RESULT $CPU $run $status ($(( $(date +%s) - start ))s)"
done
rm -f /tmp/st-qemu.log
exit $FAILED
