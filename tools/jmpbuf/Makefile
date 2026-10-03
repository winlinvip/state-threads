.PHONY: default clean

LDLIBS=
CFLAGS=-g -O0

OS_NAME 	= $(shell uname -s)
ST_TARGET 	= linux-debug
ifeq ($(OS_NAME), Darwin)
ST_TARGET	= darwin-debug
CPU_ARCHS 	= $(shell g++ -dM -E - </dev/null |grep -q '__x86_64' && echo x86_64)
CPU_ARCHS 	+= $(shell g++ -dM -E - </dev/null |grep -q '__aarch64' && echo arm64)
CFLAGS      += -arch $(CPU_ARCHS)
endif

# The warning and output flags, the executable suffix, and the files to clean.
WARNFLAGS   = -Wall
LINK_OUT    = -o $(EMPTY)
PP_OUT      = -o $(EMPTY)
EXE         =
CLEAN_FILES = jmpbuf jmpbuf.E.txt jmpbuf.dSYM

# Native Windows x64 with MSVC (cl), the WIN64 platform of ../../Makefile. Run GNU make from Git Bash or
# PowerShell with the MSVC environment on PATH, where uname -s is MINGW64_NT-* or MSYS_NT-*. The -E output of
# cl goes to stdout, so it is redirected to the file.
ifneq ($(filter MINGW% MSYS%,$(OS_NAME)),)
CC          = cl
CFLAGS      = -nologo -Z7 -Od
WARNFLAGS   = -W4
LINK_OUT    = -Fe
PP_OUT      = >
EXE         = .exe
CLEAN_FILES += jmpbuf.exe jmpbuf.obj jmpbuf.ilk jmpbuf.pdb
endif

default: ./jmpbuf$(EXE) ./jmpbuf.E.txt

./jmpbuf$(EXE):  jmpbuf.c $(LDLIBS)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) $(WARNFLAGS) $(LINK_OUT)$@ $^ $(LDLIBS)

./jmpbuf.E.txt: jmpbuf.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) $(WARNFLAGS) -E $(PP_OUT)jmpbuf.E.txt $^ $(LDLIBS)

clean:
	rm -rf $(CLEAN_FILES)

