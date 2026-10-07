.PHONY: default clean

include ../tool.mk

LDLIBS=$(ST_OBJ_DIR)/libst.a -ldl
CFLAGS=-g -O0 -rdynamic -I$(ST_OBJ_DIR)

OS_NAME 	= $(shell uname -s)
ST_TARGET 	= linux-debug
ifeq ($(OS_NAME), Darwin)
ST_TARGET	= darwin-debug
# The CPU to build for: CPU_ARCHS from the environment, such as x86_64 on Apple Silicon, or the host CPU.
ifndef CPU_ARCHS
CPU_ARCHS 	= $(shell g++ -dM -E - </dev/null |grep -q '__x86_64' && echo x86_64)
CPU_ARCHS 	+= $(shell g++ -dM -E - </dev/null |grep -q '__aarch64' && echo arm64)
endif
CFLAGS      += -arch $(CPU_ARCHS)
endif
# glibc backtrace() walks the stack with the unwind tables, which GCC leaves out of C code on some CPUs, such as arm.
ifeq ($(OS_NAME), Linux)
CFLAGS      += -funwind-tables
endif

# The warning and output flags, the executable suffix, and the files to clean.
WARNFLAGS   = -Wall
LINK_OUT    = -o $(EMPTY)
EXE         =
CLEAN_FILES = backtrace backtrace.dSYM

# Native Windows x64 with MSVC (cl), the WIN64 platform of ../../Makefile. Run GNU make from Git Bash or
# PowerShell with the MSVC environment on PATH, where uname -s is MINGW64_NT-* or MSYS_NT-*. The library
# brings ws2_32.lib itself.
ifneq ($(filter MINGW% MSYS%,$(OS_NAME)),)
LDLIBS      = $(ST_OBJ_DIR)/libst.a
ST_TARGET   = win64-debug
CC          = cl
CFLAGS      = -nologo -Z7 -Od -I$(ST_OBJ_DIR)
WARNFLAGS   = -W4
LINK_OUT    = -Fe
EXE         = .exe
CLEAN_FILES += backtrace.exe backtrace.obj backtrace.ilk backtrace.pdb
endif

$(BIN_DIR)/backtrace$(EXE): backtrace.c $(LDLIBS)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) $(WARNFLAGS) $(LINK_OUT)$@ $< $(LDLIBS)

clean:
	cd ../.. && make clean
	rm -rf $(CLEAN_FILES)

$(LDLIBS):
	cd ../.. && make $(ST_TARGET)

