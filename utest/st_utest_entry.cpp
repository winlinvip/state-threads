/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2013-2026 The SRS Authors */

// A white-box utest, which reads the saved context of a thread through the internal headers of ST. It does not include
// st_utest.hpp, whose helpers for Windows clash with the ones in md.h.
#include <gtest/gtest.h>

#include <st.h>
#include <stdint.h>
#include <string.h>

// The utest is built without the defines that ../Makefile gives the library, so set the OS for md.h here, and DEBUG,
// because the utest links the debug library, and DEBUG changes the layout of _st_thread_t.
#if !defined(DARWIN) && !defined(LINUX) && !defined(CYGWIN64) && !defined(WIN64)
#if defined(_WIN64)
#define WIN64
#elif defined(__APPLE__)
#define DARWIN
#elif defined(__CYGWIN__)
#define CYGWIN64
#elif defined(__linux__)
#define LINUX
#endif
#endif
#ifndef DEBUG
#define DEBUG
#endif
// md.h declares the assembly functions without C linkage.
extern "C" {
#include <common.h>
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// The utest for the accessors of the saved context, MD_GET_SP, MD_GET_PC and MD_GET_FP in md.h: each reads the slot of
// the jmpbuf that _st_md_cxt_save stores and _st_md_cxt_restore loads, the stack pointer, the address it jumps to, and
// the frame pointer.
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// The save stores every register it keeps inside the jmpbuf, and writes nothing after it. The jmpbuf is the last field
// of the thread, and the keys follow it on the stack, so a save that stores more overwrites the keys of the thread.
TEST(ContextAccessorTest, SaveStaysInsideTheJmpbuf)
{
    struct {
        _st_jmp_buf_t jb;
        unsigned char room[256];
    } s;
    memset(&s, 0xa5, sizeof(s));
    _st_md_cxt_save(s.jb);

    int changed = 0;
    for (int i = 0; i < (int)sizeof(s.room); i++) {
        if (s.room[i] != 0xa5) {
            changed = i + 1;
        }
    }
    EXPECT_EQ(0, changed) << "the save wrote " << changed << " bytes past the " << sizeof(_st_jmp_buf_t)
                          << "-byte jmpbuf";
}

#ifndef _WIN32 // MSVC has no frame address builtin; the entry test below uses the accessors on Windows.
// Saves the context of its caller into t, and returns the frame address of its caller. The saved SP and frame pointer
// are the ones of this function's frame after the save returns, and the saved PC is the return address into it.
static __attribute__((noinline)) uintptr_t entry_test_save(_st_thread_t* t)
{
    uintptr_t frame = (uintptr_t)__builtin_frame_address(0);
    _st_md_cxt_save(t->context);
    return frame;
}

TEST(ContextAccessorTest, ReadTheSavedSpPcAndFramePointer)
{
    // Room after the jmpbuf, the last field of the thread, as st_thread_create leaves for the keys, so a save that
    // stores more than the jmpbuf holds does not overwrite this frame.
    struct {
        _st_thread_t t;
        intptr_t room[32];
    } s;
    memset(&s, 0, sizeof(s));
    uintptr_t frame = entry_test_save(&s.t);

    uintptr_t sp = (uintptr_t)MD_GET_SP(&s.t);
    uintptr_t pc = (uintptr_t)MD_GET_PC(&s.t);
    uintptr_t fp = (uintptr_t)MD_GET_FP(&s.t);

    // The SP is in the frame of entry_test_save, a small frame, near its frame address.
    uintptr_t distance = sp > frame ? sp - frame : frame - sp;
    EXPECT_LT(distance, (uintptr_t)4096) << "sp=" << (void*)sp << ", frame=" << (void*)frame;

    // The PC is the return address, in the code of entry_test_save, a small function.
    uintptr_t code = (uintptr_t)&entry_test_save;
    EXPECT_GT(pc, code) << "pc=" << (void*)pc << ", function=" << (void*)code;
    EXPECT_LT(pc, code + 4096) << "pc=" << (void*)pc << ", function=" << (void*)code;

    // The frame pointer is the frame address, as the utest builds with -O0, which keeps a frame pointer. Thumb code on
    // arm keeps its frame pointer in r7, not in r11, the fp slot of the jmpbuf.
#if !(defined(__arm__) && defined(__thumb__))
    EXPECT_EQ(frame, fp) << "fp=" << (void*)fp << ", frame=" << (void*)frame;
#else
    (void)fp;
#endif
}
#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// The utest for the assembly entry of a new thread, _st_md_thread_start: st_thread_create sets the saved context with
// MD_INIT_THREAD_ENTRY, so the first restore of the thread enters the entry on the new stack, as if it were called
// from address 0, with the ABI stack alignment and a null frame pointer, which ends stack walks there. Built only on
// the OS and CPU that define MD_INIT_THREAD_ENTRY.
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifdef MD_INIT_THREAD_ENTRY
// The stack alignment the ABI wants at a call, and the size of the return address that a call pushes on x86, which
// the entry finds at its SP, so SP plus that size is aligned.
#if defined(__x86_64__) || defined(__amd64__) || defined(_M_X64) || defined(_M_AMD64)
#define ST_ENTRY_TEST_ALIGN 16
#define ST_ENTRY_TEST_RETURN_ADDRESS 8
#elif defined(__i386__)
#define ST_ENTRY_TEST_ALIGN 16
#define ST_ENTRY_TEST_RETURN_ADDRESS 4
#elif defined(__aarch64__) || defined(__riscv) || defined(__loongarch64) || defined(__mips64)
#define ST_ENTRY_TEST_ALIGN 16
#define ST_ENTRY_TEST_RETURN_ADDRESS 0
#elif defined(__arm__) || defined(__mips__)
#define ST_ENTRY_TEST_ALIGN 8
#define ST_ENTRY_TEST_RETURN_ADDRESS 0
#else
#error "Unknown CPU architecture"
#endif

static void* entry_test_noop(void* /*arg*/)
{
    return NULL;
}

TEST(ThreadEntryTest, NewThreadStartsInTheAssemblyEntry)
{
    st_thread_t trd = st_thread_create(entry_test_noop, NULL, 0, 0);
    ASSERT_TRUE(trd != NULL);
    _st_thread_t* t = (_st_thread_t*)trd;

    // The keys follow the thread struct on its stack, so this checks the utest sees the library's _st_thread_t.
    ASSERT_EQ((void*)(t + 1), (void*)t->private_data) << "the layout of _st_thread_t differs from the library's";

    intptr_t pc = (intptr_t)MD_GET_PC(t);
    intptr_t sp = (intptr_t)MD_GET_SP(t);
    intptr_t fp = (intptr_t)MD_GET_FP(t);

    EXPECT_EQ((intptr_t)&_st_md_thread_start, pc);
    EXPECT_EQ(0, (int)((sp + ST_ENTRY_TEST_RETURN_ADDRESS) % ST_ENTRY_TEST_ALIGN)) << "sp=" << (void*)sp;
    EXPECT_EQ(0, fp);
#if ST_ENTRY_TEST_RETURN_ADDRESS
    EXPECT_TRUE(*(void**)sp == NULL) << "return address=" << *(void**)sp;
#endif

    // Run the thread, which starts in the entry and exits.
    st_usleep(0);
}
#endif
