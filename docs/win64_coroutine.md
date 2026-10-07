# How coroutines work on native Windows x64, and start on every CPU

This note explains how State Threads switches and starts threads (coroutines) on native Windows x64 with
MSVC (`WIN64`), and why a new thread starts in an assembly entry, `_st_md_thread_start`, instead of
returning a second time from a context save. Windows x64 had the entry first; now every Linux and macOS CPU
has one too, and only Cygwin64 keeps the old start. The code is in `md_win64.asm`, `md_linux.S`,
`md_linux2.S`, `md_darwin.S`, the `MD_INIT_THREAD_ENTRY` macros in `md.h`, and `st_thread_create` in
`sched.c`.

## A thread is a saved set of registers

Running code is described by the CPU registers and the stack that `rsp` points into. To pause a thread, ST
saves the registers into its jmpbuf (`thread->context`); to resume it, ST loads them back. Two assembly
functions in `md_win64.asm` do this:

- `_st_md_cxt_save(env)`, like `setjmp`, stores the registers into `env` and returns 0.
- `_st_md_cxt_restore(env, val)`, like `longjmp`, loads the registers from `env`, sets `rsp`, and jumps to
  the saved PC. The CPU continues right after the `_st_md_cxt_save` call that filled `env`, as if that call
  returned a second time, with `val` (1 if `val` is 0).

The jmpbuf holds every register the Windows x64 ABI calls callee-saved, which a function must give back
unchanged, so the compiler may keep values in them across a call. A context switch is such a call.

| Slot | Content | Why |
| --- | --- | --- |
| 0-7 | `rbx`, `rbp`, `rdi`, `rsi`, `r12`-`r15` | Callee-saved integer registers. On Linux, `rdi` and `rsi` are not. |
| 8 | `rsp` | The stack the thread runs on (`MD_GET_SP`). |
| 9 | PC | Where the thread continues: the return address of the save. |
| 10-12 | TIB `StackBase`, `StackLimit`, `DeallocationStack` | The bounds Windows keeps for the current stack (see below). |
| after 12 | MXCSR, x87 control word, `xmm6`-`xmm15` | Also callee-saved on Windows. On Linux, no `xmm` register is. |

## Switching between two threads

A thread that blocks saves itself and restores the next one:

```c
if (_st_md_cxt_save(me->context) == 0) {   /* save me, returns 0 */
    _st_md_cxt_restore(next->context, 1);  /* jump into next */
}
/* Later, when another thread restores me, the save returns 1 here and I go on. */
```

The next thread was paused the same way, so its jmpbuf holds its own stack, PC, and registers, and it
continues inside a function that really runs on that stack.

## Starting a new thread

A new thread has never run, so it has never called `_st_md_cxt_save`; its first jmpbuf must be made up: a
stack pointer into its new, empty stack, and a PC to start at.

### The old start: save, then patch the SP

Before v1.9.3, Linux and macOS started a new thread like this, and Cygwin64 still does:

```c
if (_st_md_cxt_save(thread->context)) {  /* 1. save the creator's registers */
    _st_thread_main();                   /* 3. the new thread starts here */
}
MD_GET_SP(thread) = stack->sp;           /* 2. point only the SP at the new stack */
```

The first restore of this jmpbuf jumps back into `st_thread_create`, the save returns 1, and the code calls
`_st_thread_main`. But that code now runs on the new stack, where `st_thread_create` was never called:

```
creator's stack                       new thread's stack
+---------------------------+         +---------------------------+
| st_thread_create locals,  |         | empty                     | <- rsp after the restore
| saved registers, return   |         |                           |
+---------------------------+         +---------------------------+
```

After the second return, a read of a local from the stack frame gets garbage, and a value the compiler kept
in a register from before the save is right only if it is one of the callee-saved registers the restore
loads back. The trick works only while the compiler emits nothing there but "if 1, call `_st_thread_main`".
The C language does not promise that, and the compiler does not know that `_st_md_cxt_save` returns twice.

On Linux it held in practice: an access to a `__thread` variable such as `_st_this_thread` is one
instruction (`mov %fs:offset` on x86-64, `tpidr_el0` on arm64), so there is nothing worth computing before
the save, and GCC and Clang generated safe code there for decades. Still, the new thread inherited its
creator's callee-saved registers, and its outermost frame was a frame of `st_thread_create` that was never
called, so a stack walk had no clean end.

On Windows it held only by luck. With `/O2` and with `/GL` (LTCG), MSVC inlines `_st_thread_main` into
`st_thread_create`. A Windows TLS access takes several steps (`gs:[58h]`, the TLS array, `_tls_index`, the
offset), so MSVC computes the TLS base and `&_st_this_vp` before the save, keeps them in `r13` and `r14`
(`rbp` and `r15` with LTCG), and uses them after the second return. That is right only because those
registers are callee-saved; a spill to the stack would crash the new thread.

### The new start: an assembly entry

Every platform but Cygwin64 defines `MD_INIT_THREAD_ENTRY` in `md.h`, and `st_thread_create` starts a new
thread like this:

```c
_st_md_cxt_save(thread->context);  /* 1. fill the jmpbuf as a template */
MD_GET_SP(thread) = stack->sp;     /* 2. point the SP at the new stack */
MD_INIT_THREAD_ENTRY(thread);      /* 3. align the SP, start in _st_md_thread_start, null frame pointer */
```

The save still runs, but only to fill the jmpbuf with valid values, such as the FPU control words, or `$gp`
on MIPS. The new thread never resumes at it: the first restore of the jmpbuf jumps to `_st_md_thread_start`,
a small function written in assembly, on the new stack, so no compiler decides what runs first there. The
entry calls `_st_thread_main`, which runs the thread function and then `st_thread_exit`, so it never
returns; a trap instruction after the call says so.

### Windows x64: the entry in detail

On `WIN64`, `MD_INIT_THREAD_ENTRY` does:

```c
sp = align_down(stack->sp, 16) - 8;  /* 8 mod 16, as at the entry of a function */
*(void **)sp = NULL;                 /* a return address of 0 */
jmpbuf[8] = sp;                      /* SP */
jmpbuf[9] = _st_md_thread_start;     /* PC */
jmpbuf[1] = 0;                       /* rbp, not the creator's */
```

The new stack is then:

```
higher addresses: the thread object and its keys
+----------------------+
| pad, 128 bytes       |
+----------------------+ <- 16-byte aligned
| 0, return address    | <- the SP in the jmpbuf, 8 mod 16
+----------------------+
| free stack, grows down
v
```

The first restore loads the registers, sets `rsp` to that slot, and jumps to `_st_md_thread_start`. To the
CPU this is a normal function call from address 0: a call pushes the return address and jumps, and the
"pushed" return address is the 0 written there.

```asm
_st_md_thread_start PROC FRAME
    sub rsp, 40          ; the callee's 32-byte home space, and 8 bytes to align rsp to 16
    .allocstack 40       ; unwind info: this frame is 40 bytes
    .endprolog
    call _st_thread_main ; run start(arg), then st_thread_exit
    int 3                ; never reached; st_thread_exit never returns
_st_md_thread_start ENDP
```

- The Windows x64 ABI wants `rsp` 16-byte aligned at every `call`, so it is 8 mod 16 at the entry of a
  function. The entry starts in exactly that state, and `sub rsp, 40` aligns it again for the call. A wrong
  alignment breaks aligned SSE instructions such as `movaps`.
- `_st_thread_main` is ordinary C with a normal frame. It runs the thread function and then
  `st_thread_exit`, which switches to another thread and never comes back.
- The new thread never runs a line of `st_thread_create`. The only code between the restore and
  `_st_thread_main` is the four instructions above, and the registers the creator saved are left over and
  never read. So the start no longer depends on how the compiler uses that frame or its registers after the
  save returns twice, at `/Od`, `/O2`, or `/GL`.

The restore itself is the same for every switch; only the first jmpbuf of a new thread differs.

### Every other CPU

The entry of every Linux and macOS CPU has the same shape. `MD_INIT_THREAD_ENTRY` aligns the saved SP as
the ABI wants at a function entry, sets the saved PC to `_st_md_thread_start`, and nulls the saved frame
pointer. The entry nulls the frame pointer and the return address register again, marks the return address
undefined for DWARF unwinders, and calls `_st_thread_main`.

| Platform | File | SP at the entry | Return address | Nulled | Unwind mark |
| --- | --- | --- | --- | --- | --- |
| Windows x64 | `md_win64.asm` | 8 mod 16 | 0 on the stack | `rbp` | `PROC FRAME`, `.allocstack 40` |
| Linux and macOS x86_64 | `md_linux.S`, `md_darwin.S` | 8 mod 16 | 0 on the stack | `rbp` | `.cfi_undefined rip` |
| Linux i386 | `md_linux.S` | 12 mod 16 | 0 on the stack | `ebp` | `.cfi_undefined eip` |
| Linux and macOS aarch64 | `md_linux2.S`, `md_darwin.S` | 16-byte aligned | `x30` | `x29`, `x30` | `.cfi_undefined x30` |
| Linux arm | `md_linux2.S` | 8-byte aligned | `lr` | `fp`, `r7`, `lr` | `.cfi_undefined lr`, EHABI `.save {fp, lr}` |
| Linux riscv64 | `md_linux2.S` | 16-byte aligned | `ra` | `s0`, `ra` | `.cfi_undefined ra` |
| Linux loongarch64 | `md_linux2.S` | 16-byte aligned | `ra` | `fp`, `ra` | `.cfi_undefined 1` (`ra`) |
| Linux mips64, mips64el (n64) | `md_linux2.S` | 16-byte aligned | `$ra` | `$fp`, `$ra` | `.cfi_undefined $ra` |
| Linux mips, mipsel (o32) | `md_linux2.S` | 8-byte aligned | `$ra` | `$fp`, `$ra` | `.cfi_undefined $ra` |

- **x86:** a `call` pushes the return address, so a function starts with SP 8 (x86_64) or 4 (i386) below a
  16-byte boundary. The macro writes a null return address there, and the entry subtracts the rest to align
  SP to 16 at its own call. On i386 the entry also puts the GOT address in `ebx`, which a PIC call through
  the PLT needs.
- **RISC CPUs:** the restore jumps to the saved return address register, so that slot holds the entry, and
  the SP needs only to be aligned. The entry then sets the register to 0 before its call.
- **arm:** the entry is ARM code, and the restore's `bx lr` switches to it from Thumb C code. glibc
  `backtrace()` and C++ exceptions walk ARM EHABI tables, not DWARF, so the entry pushes two null words with
  `.save {fp, lr}`: the walk lists the entry, pops a return address of 0, and stops. GCC leaves unwind tables
  out of C code on arm and MIPS, so the Linux library builds with `-funwind-tables`.
- **MIPS:** PIC code computes `$gp` from `$t9`, which must hold the address of the function it enters, and
  the restore does not set it. So the entry finds its own address with `bal`, computes `$gp` from it, and
  calls `_st_thread_main` through `$t9`. On o32 it also reserves the 16-byte argument save area of the callee.
- **macOS:** `backtrace()` follows the frame pointer chain, so the null `rbp` or `x29` ends it.

The tests check the entry on every CPU: `ThreadEntryTest` in `utest/st_utest_entry.cpp` reads the jmpbuf of
a new thread before it runs (the PC, the alignment of the SP, the null frame pointer, and on x86 the null
return address), and `tools/backtrace` checks that a backtrace in a thread ends at a return address inside
`_st_md_thread_start`. The README tells how to run them on every CPU with QEMU.

## Exceptions and stack walks (SEH)

Structured Exception Handling (SEH) is how Windows handles errors raised while code runs: a hardware fault
such as an access violation is an SEH exception, and MSVC implements a C++ `throw` as an SEH exception too
(code `0xE06D7363`). To find a handler (a `catch` or an `__except`), Windows walks the stack frame by frame,
from the current function to its callers. Debuggers, crash dumps, and `RtlCaptureStackBackTrace` walk the
stack the same way.

On x64, Windows does not follow `rbp` chains. Every function has an entry in the unwind tables (`.pdata`
and `.xdata`) that the compiler or assembler generates. For a PC, the entry tells how far the function moved
`rsp` and which registers it saved, so Windows finds the return address and steps to the caller.

Windows also checks every step against the stack bounds in the thread information block (TIB). If `rsp`
leaves `StackLimit`..`StackBase`, it takes the stack as corrupt and ends the process. That is why the
context switch saves and loads the TIB bounds (slots 10-12), and `st_thread_create` sets them for a new
thread (`MD_INIT_STACK_BOUNDS`). Without them, any exception on a thread stack would look like a corrupt
stack.

With the save-then-patch-SP trick, the outermost frame of a new thread would be code of `st_thread_create`
on a stack it was never called on. Its unwind entry points to a return address above the SP, in the pad or
the thread object, which is not a return address, so a walk would step into a random caller. With the assembly entry, the walk ends
cleanly:

```
thread function      -> unwind info: returns to _st_thread_main
_st_thread_main      -> unwind info: returns to _st_md_thread_start
_st_md_thread_start  -> PROC FRAME, .allocstack 40: the return address is at rsp+40, it is 0
0                    -> no caller: the end of the stack
```

`PROC FRAME`, `.allocstack`, and `.endprolog` make `ml64` generate the unwind entry of the assembly
function; without them, Windows could not step over it. A return address of 0 is the usual mark of the
outermost frame. So a backtrace in a thread function has exactly three frames: the thread function,
`_st_thread_main`, and `_st_md_thread_start`. A C++ `throw` is caught across any depth of frames, and an
unhandled exception ends the process with its exception code instead of hanging.

Linux has the same idea with DWARF `.eh_frame` instead of `.pdata`, but with no TIB check: glibc
`backtrace()` and C++ exceptions use the DWARF unwinder of libgcc (EHABI on arm), and the undefined return
address of the entry ends the walk there. macOS `backtrace()` stops at the null frame pointer. C++ code on a
thread stack normally catches its exceptions inside the thread function.

## Summary

| | Old start (Cygwin64 only) | Assembly entry (Linux, macOS, Windows x64) |
| --- | --- | --- |
| PC of a new thread | In `st_thread_create`, after the save | `_st_md_thread_start`, in assembly |
| SP of a new thread | The new stack top | The new stack top, aligned as at a function entry |
| First code on the new stack | The tail of `st_thread_create`, from the compiler | A few instructions written by hand |
| Depends on the optimizer | Yes, in theory | No |
| Frame pointer and return address | The creator's | Null |
| Stack walk at the top | Not defined | Ends at the entry |
