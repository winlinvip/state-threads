#!/bin/bash
#
# Build ST for one macOS CPU, and run the utest and the tools. On Apple Silicon, x86_64 runs under Rosetta 2.
#
#   ./auto/darwin.sh <cpu> [utest|tools|tools-malloc|all]
#
# CPUs: arm64, x86_64.
# The second argument picks what to run, all by default:
#   utest         st_utest
#   tools         auto/tools.sh
#   tools-malloc  auto/tools.sh with EXTRA_CFLAGS=-DMALLOC_STACK
#   all           all three, in that order, and every one runs even when another fails
#
# It exports CPU_ARCHS, which the Makefiles pass to -arch instead of the host CPU, and builds in place in
# DARWIN_<cpu>_DBG, so the CPUs and the native build never share objects. Every binary runs with
# arch -<cpu>, which auto/tools.sh takes from ST_TOOL_RUN, so a binary built for the wrong CPU fails to start.
#
# It prints one line per run, "RESULT <cpu> <run> PASS|FAIL (<seconds>s)", with the log of a failed run
# before it, and exits 1 when any run failed.
#
# Examples:
#   ./auto/darwin.sh x86_64
#   ./auto/darwin.sh arm64 utest

cd "$(dirname "$0")/.." || exit 1

CPU=$1
WHAT=${2:-all}

case $CPU in
    arm64|x86_64) ;;
    *)
        echo "Usage: $0 <cpu> [utest|tools|tools-malloc|all]" >&2
        echo "CPUs: arm64 x86_64" >&2
        exit 2
        ;;
esac
case $WHAT in
    utest|tools|tools-malloc) RUNS=$WHAT ;;
    all) RUNS="utest tools tools-malloc" ;;
    *) echo "Usage: $0 <cpu> [utest|tools|tools-malloc|all]" >&2; exit 2 ;;
esac
if [[ $(uname -s) != Darwin ]]; then
    echo "FAILED $0 runs only on macOS" >&2
    exit 2
fi

export CPU_ARCHS=$CPU
export TARGETDIR=DARWIN_${CPU}_DBG
export ST_TOOL_RUN="arch -$CPU"

# Build the library with EXTRA_CFLAGS $1, then the utest, and run it. -B rebuilds the library, so it never
# keeps objects built with other flags; the utest objects depend on the library and follow it.
run_utest() {
    make -B darwin-debug EXTRA_CFLAGS="$1" || return 1
    make -C utest EXTRA_CFLAGS="$1" || return 1
    $ST_TOOL_RUN ./obj/st_utest
}

LOG=/tmp/st-darwin.log
FAILED=0
for run in $RUNS; do
    start=$(date +%s)
    status=PASS
    case $run in
        utest) run_utest "" > $LOG 2>&1 || status=FAIL ;;
        tools) ./auto/tools.sh > $LOG 2>&1 || status=FAIL ;;
        tools-malloc) EXTRA_CFLAGS=-DMALLOC_STACK ./auto/tools.sh > $LOG 2>&1 || status=FAIL ;;
    esac
    if [[ $status == FAIL ]]; then
        tail -40 $LOG | sed 's/^/  | /'
        FAILED=1
    fi
    echo "RESULT $CPU $run $status ($(( $(date +%s) - start ))s)"
done
rm -f /tmp/st-darwin.log
exit $FAILED
