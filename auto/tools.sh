#!/bin/bash
#
# Build ST, then run every integration tool in tools/ under each event system.
#
# The build comes from the environment, empty by default:
#   EXTRA_CFLAGS  passed to the library build, such as -DMALLOC_STACK
#   LDFLAGS       passed to the tool link, such as -fsanitize=address
#   ST_TOOL_RUN   the launcher of each tool, such as "qemu-riscv64 -L /usr/riscv64-linux-gnu" for a
#                 cross build, as auto/qemu.sh sets it with CC and the rest of the toolchain
#   CPU_ARCHS     on macOS, the CPU the Makefiles build for, such as x86_64 on Apple Silicon, run with
#                 ST_TOOL_RUN="arch -x86_64", as auto/darwin.sh sets them
#   TARGETDIR     the build folder of the library, relative to the ST root, such as LINUX_riscv64_qemu_DBG, as
#                 auto/qemu.sh sets it; each tool is then built and run in $TARGETDIR/tools/<name>, the obj link
#                 is left alone, and builds for several CPUs can run at once. By default the library is in obj,
#                 and each tool in tools/<name>.
#
# Examples:
#   ./auto/tools.sh
#   ./auto/tools.sh tcp udp
#   EXTRA_CFLAGS=-DMALLOC_STACK ./auto/tools.sh
#   EXTRA_CFLAGS="-DMALLOC_STACK -DMD_ASAN -fsanitize=address -fno-omit-frame-pointer" \
#       LDFLAGS=-fsanitize=address ./auto/tools.sh
#
# The arguments name the tools to run, every folder in tools/ by default.
# Each tool reads ST_TOOL_EVENTSYS, select or alt. It prints "<name> <eventsys> OK"
# per run, or "FAILED <name> <eventsys>" with the output, and exits 1 at the first failure.
# A tool that this platform does not support prints only "SKIP <name>: <why>" and exits 0,
# which shows as "SKIP <name>: <why> (<eventsys>)".
#
# On native Windows, run it from Git Bash with the MSVC environment on PATH, where
# uname -s is MINGW64_NT-* or MSYS_NT-*: it builds win64-debug and runs <name>.exe.

cd "$(dirname "$0")/.." || exit 1

ST_TARGET=linux-debug
EXE=
case $(uname -s) in
    Darwin) ST_TARGET=darwin-debug ;;
    MINGW*|MSYS*) ST_TARGET=win64-debug; EXE=.exe ;;
esac

tool_dirs=()
for name in "$@"; do
    if [[ ! -f tools/$name/Makefile ]]; then
        echo "FAILED no tool $name in tools/"
        exit 1
    fi
    tool_dirs+=("tools/$name/")
done
if [[ ${#tool_dirs[@]} == 0 ]]; then
    tool_dirs=(tools/*/)
fi

echo "Build ST with make -B $ST_TARGET EXTRA_CFLAGS=\"$EXTRA_CFLAGS\""
# -B rebuilds every object, so a change of flags never links a stale library.
if ! out=$(make -B $ST_TARGET EXTRA_CFLAGS="$EXTRA_CFLAGS" 2>&1); then
    echo "$out"
    echo "FAILED build ST"
    exit 1
fi

for dir in "${tool_dirs[@]}"; do
    name=$(basename "$dir")
    # -W relinks the tool, because a binary is shared by builds with other flags, and in tools/<name> by platforms too.
    # A tool is C, <name>.c, or C++, <name>.cpp.
    src=$name.c
    if [[ -f $dir$name.cpp ]]; then
        src=$name.cpp
    fi
    if ! out=$(make -C "$dir" -W "$src" LDFLAGS="$LDFLAGS" 2>&1); then
        echo "$out"
        echo "FAILED build $name"
        exit 1
    fi

    # The tool runs in the folder of its binary, as tools/tool.mk puts it.
    bin_dir=$dir
    if [[ -n $TARGETDIR ]]; then
        bin_dir=$TARGETDIR/tools/$name
    fi
    for eventsys in select alt; do
        if ! out=$(cd "$bin_dir" && ST_TOOL_EVENTSYS=$eventsys $ST_TOOL_RUN "./$name$EXE" 2>&1); then
            echo "$out"
            echo "FAILED $name $eventsys"
            exit 1
        fi
        if [[ $out == "SKIP $name:"* ]]; then
            echo "$out ($eventsys)"
            continue
        fi
        echo "$name $eventsys OK"
    done
done

echo "All tools OK"
