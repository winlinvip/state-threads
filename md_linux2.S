/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2021-2022 The SRS Authors */

/* If user disable the ASM, such as avoiding bugs in ASM, donot compile it. */
#if !defined(MD_ST_NO_ASM)

#if defined(__aarch64__)

    /****************************************************************/
    /* See https://developer.arm.com/documentation/102374/0100/Function-calls */
    /* See https://developer.arm.com/documentation/102374/0100/Procedure-Call-Standard */
    /* See https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst#machine-registers */
    /* See https://wiki.cdot.senecacollege.ca/wiki/AArch64_Register_and_Instruction_Quick_Start */
    /* See https://chromium.googlesource.com/native_client/nacl-glibc/+/glibc-2.21/sysdeps/aarch64/__longjmp.S */
    /* See https://chromium.googlesource.com/native_client/nacl-glibc/+/glibc-2.21/sysdeps/aarch64/setjmp.S */

    /* The called routine is expected to preserve r19-r28 *** These registers are generally
        safe to use in your program. */
    #define JB_X19            0
    #define JB_X20            1
    #define JB_X21            2
    #define JB_X22            3
    #define JB_X23            4
    #define JB_X24            5
    #define JB_X25            6
    #define JB_X26            7
    #define JB_X27            8
    #define JB_X28            9
    /* r29 and r30 are used as the frame register and link register (avoid) */
    #define JB_X29           10
    #define JB_LR            11
    /* In AArch64, register encoding '31' is context-dependent (there is no "x31"):
        - In stack-related instructions, it refers to SP (the stack pointer)
        - In other instructions, it refers to XZR (the zero register) */
    #define JB_SP		 13

    /* FP registers */
    #define JB_D8		 14
    #define JB_D9		 15
    #define JB_D10		 16
    #define JB_D11		 17
    #define JB_D12		 18
    #define JB_D13		 19
    #define JB_D14		 20
    #define JB_D15		 21

    	.file "md.S"
    	.text

    	/* _st_md_cxt_save(__jmp_buf env) */
    	.globl _st_md_cxt_save
    	.type _st_md_cxt_save, %function
    	.align 4
    _st_md_cxt_save:
    	stp	x19, x20, [x0, #JB_X19<<3]
    	stp	x21, x22, [x0, #JB_X21<<3]
    	stp	x23, x24, [x0, #JB_X23<<3]
    	stp	x25, x26, [x0, #JB_X25<<3]
    	stp	x27, x28, [x0, #JB_X27<<3]
    	stp	x29, x30, [x0, #JB_X29<<3]

    	stp	 d8,  d9, [x0, #JB_D8<<3]
    	stp	d10, d11, [x0, #JB_D10<<3]
    	stp	d12, d13, [x0, #JB_D12<<3]
    	stp	d14, d15, [x0, #JB_D14<<3]
    	mov	x2,  sp
    	str	x2,  [x0, #JB_SP<<3]

    	mov	x0, #0
    	ret
    	.size _st_md_cxt_save, .-_st_md_cxt_save

    /****************************************************************/

    	/* _st_md_cxt_restore(__jmp_buf env, int val) */
    	.globl _st_md_cxt_restore
    	.type _st_md_cxt_restore, %function
    	.align 4
    _st_md_cxt_restore:
    	ldp	x19, x20, [x0, #JB_X19<<3]
    	ldp	x21, x22, [x0, #JB_X21<<3]
    	ldp	x23, x24, [x0, #JB_X23<<3]
    	ldp	x25, x26, [x0, #JB_X25<<3]
    	ldp	x27, x28, [x0, #JB_X27<<3]

    	ldp	x29, x30, [x0, #JB_X29<<3]

    	ldp	 d8,  d9, [x0, #JB_D8<<3]
    	ldp	d10, d11, [x0, #JB_D10<<3]
    	ldp	d12, d13, [x0, #JB_D12<<3]
    	ldp	d14, d15, [x0, #JB_D14<<3]

    	ldr	x5, [x0, #JB_SP<<3]
    	mov	sp, x5

    	cmp	x1, #0
    	mov	x0, #1
    	csel	x0, x1, x0, ne
    	/* Use br instead of ret because ret is guaranteed to mispredict */
    	br	x30
    	.size _st_md_cxt_restore, .-_st_md_cxt_restore

    /****************************************************************/

    /*
     * void _st_md_thread_start(void), the entry of a new thread, never returns.
     * MD_INIT_THREAD_ENTRY in md.h points the link register of the new thread's jmpbuf here, its
     * SP at a 16-byte boundary, and its x29 at 0. So the first _st_md_cxt_restore of the thread
     * branches here on the new stack, with none of its creator's frames. The undefined return
     * address ends DWARF unwinds here, and the null x29 and x30 end frame-pointer walks.
     */
    	.globl _st_md_thread_start
    	.type _st_md_thread_start, %function
    	.align 4
    _st_md_thread_start:
    	.cfi_startproc
    	.cfi_undefined x30
    	mov	x29, #0
    	mov	x30, #0
    	bl	_st_thread_main
    	/* _st_thread_main calls st_thread_exit, which never returns. */
    	brk	#0
    	.cfi_endproc
    	.size _st_md_thread_start, .-_st_md_thread_start

    /****************************************************************/










#elif defined(__arm__)

    /****************************************************************/
    /* https://github.com/ossrs/srs/issues/1282#issuecomment-445539513 */

    /* Register list for a ldm/stm instruction to load/store
       the general registers from a __jmp_buf.  */
    # define JMP_BUF_REGLIST	{v1-v6, sl, fp, sp, lr}

    	.file "md.S"
    	.text

    	/* _st_md_cxt_save(__jmp_buf env) */
    	.globl _st_md_cxt_save
    	.type _st_md_cxt_save, %function
    	.align 2
    _st_md_cxt_save:
    	mov	ip, r0

    	/* Save registers */
    	stmia	ip!, JMP_BUF_REGLIST

    #ifdef __VFP_FP__
    	/* Store the VFP registers.  */
    	/* Following instruction is vstmia ip!, {d8-d15}.  */
    	stc	p11, cr8, [ip], #64
    #endif

    #ifdef __IWMMXT__
    	/* Save the call-preserved iWMMXt registers.  */
    	/* Following instructions are wstrd wr10, [ip], #8 (etc.)  */
    	stcl	p1, cr10, [r12], #8
    	stcl	p1, cr11, [r12], #8
    	stcl	p1, cr12, [r12], #8
    	stcl	p1, cr13, [r12], #8
    	stcl	p1, cr14, [r12], #8
    	stcl	p1, cr15, [r12], #8
    #endif

    	mov	r0, #0
    	bx	lr

    	.size _st_md_cxt_save, .-_st_md_cxt_save

    /****************************************************************/

    	/* _st_md_cxt_restore(__jmp_buf env, int val) */
    	.globl _st_md_cxt_restore
    	.type _st_md_cxt_restore, %function
    	.align 2
    _st_md_cxt_restore:
    	mov	ip, r0

    	/* Restore registers */
    	ldmia	ip!, JMP_BUF_REGLIST

    #ifdef __VFP_FP__
    	/* Restore the VFP registers.  */
    	/* Following instruction is vldmia ip!, {d8-d15}.  */
    	ldc	p11, cr8, [r12], #64
    #endif

    #ifdef __IWMMXT__
    	/* Restore the call-preserved iWMMXt registers.  */
    	/* Following instructions are wldrd wr10, [ip], #8 (etc.)  */
    	ldcl	p1, cr10, [r12], #8
    	ldcl	p1, cr11, [r12], #8
    	ldcl	p1, cr12, [r12], #8
    	ldcl	p1, cr13, [r12], #8
    	ldcl	p1, cr14, [r12], #8
    	ldcl	p1, cr15, [r12], #8
    #endif

    	movs	r0, r1		/* get the return value in place */
    	moveq	r0, #1		/* can't let setjmp() return zero! */
    	bx	lr

    	.size _st_md_cxt_restore, .-_st_md_cxt_restore

    /****************************************************************/

    /*
     * void _st_md_thread_start(void), the entry of a new thread, never returns.
     * MD_INIT_THREAD_ENTRY in md.h points the link register of the new thread's jmpbuf here, its
     * SP at an 8-byte boundary, and its fp at 0. So the first _st_md_cxt_restore of the thread
     * branches here with bx on the new stack, with none of its creator's frames. The bl to
     * _st_thread_main becomes a blx when the C code is Thumb.
     *
     * The entry pushes two null words, which keep the 8-byte alignment, and its EHABI unwind entry
     * says they are the saved fp and lr. So the EHABI unwinder of glibc backtrace() and C++
     * exceptions lists the entry as the last frame, and stops at its null return address. The
     * undefined return address in the CFI ends DWARF unwinds here, such as gdb's, and the null fp,
     * r7 (the frame pointer of Thumb code) and lr end frame-pointer walks.
     */
    	.globl _st_md_thread_start
    	.type _st_md_thread_start, %function
    	.align 2
    _st_md_thread_start:
    	.fnstart
    	.cfi_startproc
    	.cfi_undefined lr
    	mov	fp, #0
    	mov	r7, #0
    	mov	lr, #0
    	.save	{fp, lr}
    	push	{fp, lr}
    	.cfi_adjust_cfa_offset 8
    	bl	_st_thread_main
    	/* _st_thread_main calls st_thread_exit, which never returns. */
    	udf	#0
    	.cfi_endproc
    	.fnend
    	.size _st_md_thread_start, .-_st_md_thread_start

    /****************************************************************/





#elif defined(__riscv)

    /****************************************************************/
    /*
     * Internal __jmp_buf layout
     * riscv-asm: https://github.com/riscv/riscv-asm-manual/blob/master/riscv-asm.md
     */
    #define JB_SP  0    /* A0, SP, Stack pointer */
    #define JB_RA  1    /* RA, Return address */
    #define JB_FP  2    /* FP/S0 Frame pointer */
    #define JB_S1  3    /* S1 Saved register*/
    #define JB_S2  4    /* S2-S11,  Saved register */
    #define JB_S3  5    /* S2-S11,  Saved register */
    #define JB_S4  6    /* S2-S11,  Saved register */
    #define JB_S5  7    /* S2-S11,  Saved register */
    #define JB_S6  8    /* S2-S11,  Saved register */
    #define JB_S7  9    /* S2-S11,  Saved register */
    #define JB_S8  10    /* S2-S11,  Saved register */
    #define JB_S9  11   /* S2-S11,  Saved register */
    #define JB_S10 12   /* S2-S11,  Saved register */
    #define JB_S11 13   /* S2-S11,  Saved register */
    #define JB_FS0 14   /* FS0-FS11, Saved FP registers, when the CPU has them */
    #define JB_FS1 15
    #define JB_FS2 16
    #define JB_FS3 17
    #define JB_FS4 18
    #define JB_FS5 19
    #define JB_FS6 20
    #define JB_FS7 21
    #define JB_FS8 22
    #define JB_FS9 23
    #define JB_FS10 24
    #define JB_FS11 25

    /* Save the low 64 bits of FS0-FS11 with D, their 32 bits with only F, and nothing with soft float. */
    #if defined(__riscv_flen) && __riscv_flen >= 64
        #define FP_SAVE fsd
        #define FP_LOAD fld
    #elif defined(__riscv_flen) && __riscv_flen == 32
        #define FP_SAVE fsw
        #define FP_LOAD flw
    #endif


    	.file "md_linux.S"
    	.text

    	/* _st_md_cxt_save(__jmp_buf env) */ /* The env is $a0, https://en.wikipedia.org/wiki/RISC-V#Register_sets */
    	.globl _st_md_cxt_save
    	.type _st_md_cxt_save, %function
    	.align 2
    _st_md_cxt_save:
	sd    sp,  JB_SP  * 8(a0)
	sd    ra,  JB_RA  * 8(a0)
	sd    s0,  JB_FP  * 8(a0)
	sd    s1,  JB_S1  * 8(a0)
	sd    s2,  JB_S2  * 8(a0)
	sd    s3,  JB_S3  * 8(a0)
	sd    s4,  JB_S4  * 8(a0)
	sd    s5,  JB_S5  * 8(a0)
	sd    s6,  JB_S6  * 8(a0)
	sd    s7,  JB_S7  * 8(a0)
	sd    s8,  JB_S8  * 8(a0)
	sd    s9,  JB_S9  * 8(a0)
	sd    s10, JB_S10 * 8(a0)
	sd    s11, JB_S11 * 8(a0)
#if defined(FP_SAVE)
	FP_SAVE fs0,  JB_FS0  * 8(a0)
	FP_SAVE fs1,  JB_FS1  * 8(a0)
	FP_SAVE fs2,  JB_FS2  * 8(a0)
	FP_SAVE fs3,  JB_FS3  * 8(a0)
	FP_SAVE fs4,  JB_FS4  * 8(a0)
	FP_SAVE fs5,  JB_FS5  * 8(a0)
	FP_SAVE fs6,  JB_FS6  * 8(a0)
	FP_SAVE fs7,  JB_FS7  * 8(a0)
	FP_SAVE fs8,  JB_FS8  * 8(a0)
	FP_SAVE fs9,  JB_FS9  * 8(a0)
	FP_SAVE fs10, JB_FS10 * 8(a0)
	FP_SAVE fs11, JB_FS11 * 8(a0)
#endif
	li    a0,  0
	jr    ra
    	.size _st_md_cxt_save, .-_st_md_cxt_save

    /****************************************************************/

    	/* _st_md_cxt_restore(__jmp_buf env, int val) */
    	.globl _st_md_cxt_restore
    	.type _st_md_cxt_restore, %function
    	.align 2
    _st_md_cxt_restore:
	ld        sp,  JB_SP  * 8(a0)
	ld        ra,  JB_RA  * 8(a0)
	ld        s0,  JB_FP  * 8(a0)
	ld        s1,  JB_S1  * 8(a0)
	ld        s2,  JB_S2  * 8(a0)
	ld        s3,  JB_S3  * 8(a0)
	ld        s4,  JB_S4  * 8(a0)
	ld        s5,  JB_S5  * 8(a0)
	ld        s6,  JB_S6  * 8(a0)
	ld        s7,  JB_S7  * 8(a0)
	ld        s8,  JB_S8  * 8(a0)
	ld        s9,  JB_S9  * 8(a0)
	ld        s10, JB_S10 * 8(a0)
	ld        s11, JB_S11 * 8(a0)
#if defined(FP_LOAD)
	FP_LOAD   fs0,  JB_FS0  * 8(a0)
	FP_LOAD   fs1,  JB_FS1  * 8(a0)
	FP_LOAD   fs2,  JB_FS2  * 8(a0)
	FP_LOAD   fs3,  JB_FS3  * 8(a0)
	FP_LOAD   fs4,  JB_FS4  * 8(a0)
	FP_LOAD   fs5,  JB_FS5  * 8(a0)
	FP_LOAD   fs6,  JB_FS6  * 8(a0)
	FP_LOAD   fs7,  JB_FS7  * 8(a0)
	FP_LOAD   fs8,  JB_FS8  * 8(a0)
	FP_LOAD   fs9,  JB_FS9  * 8(a0)
	FP_LOAD   fs10, JB_FS10 * 8(a0)
	FP_LOAD   fs11, JB_FS11 * 8(a0)
#endif
	li        a0,  1
	jr        ra
    	.size _st_md_cxt_restore, .-_st_md_cxt_restore

    /****************************************************************/

    /*
     * void _st_md_thread_start(void), the entry of a new thread, never returns.
     * MD_INIT_THREAD_ENTRY in md.h points the return address of the new thread's jmpbuf here, its
     * SP at a 16-byte boundary, and its s0 at 0. So the first _st_md_cxt_restore of the thread
     * jumps here on the new stack, with none of its creator's frames. The undefined return
     * address ends DWARF unwinds here, and the null s0 and ra end frame-pointer walks.
     */
    	.globl _st_md_thread_start
    	.type _st_md_thread_start, %function
    	.align 2
    _st_md_thread_start:
    	.cfi_startproc
    	.cfi_undefined ra
	li        s0,  0
	li        ra,  0
	call      _st_thread_main
	/* _st_thread_main calls st_thread_exit, which never returns. */
	unimp
    	.cfi_endproc
    	.size _st_md_thread_start, .-_st_md_thread_start

    /****************************************************************/






#elif defined(__mips64)

    /****************************************************************/
    /* For MIPS64, see https://s3-eu-west-1.amazonaws.com/downloads-mips/documents/MIPS_Architecture_MIPS64_InstructionSet_%20AFP_P_MD00087_06.05.pdf */

    /*
     * Internal __jmp_buf layout
     */
    #define JB_SP  0    /* Stack pointer */
    #define JB_RA  1    /* Return address */
    #define JB_GP  2    /* Global pointer */
    #define JB_S0  3    /* S0-S7, Saved temporaries */
    #define JB_S1  4    /* S0-S7, Saved temporaries */
    #define JB_S2  5    /* S0-S7, Saved temporaries */
    #define JB_S3  6    /* S0-S7, Saved temporaries */
    #define JB_S4  7    /* S0-S7, Saved temporaries */
    #define JB_S5  8    /* S0-S7, Saved temporaries */
    #define JB_S6  9    /* S0-S7, Saved temporaries */
    #define JB_S7  10   /* S0-S7, Saved temporaries */
    #define JB_FP  11   /* FP/S8 Frame pointer */
    #define JB_F24 12   /* F24-F31, the callee-saved FP registers of n64 */
    #define JB_F25 13
    #define JB_F26 14
    #define JB_F27 15
    #define JB_F28 16
    #define JB_F29 17
    #define JB_F30 18
    #define JB_F31 19

    	.file "md_linux.S"
    	.text

    	/* _st_md_cxt_save(__jmp_buf env) */ /* The env is $a0, https://en.wikipedia.org/wiki/MIPS_architecture#Calling_conventions */
    	.globl _st_md_cxt_save
    	.type _st_md_cxt_save, %function
    	.align 2
    _st_md_cxt_save:
        sd $sp,  0($a0) /* Save sp to env[0],  *(long*)($a0+ 0) =sp */
        sd $ra,  8($a0) /* Save ra to env[1],  *(long*)($a0+ 8)=ra, the return address, https://chortle.ccsu.edu/AssemblyTutorial/Chapter-26/ass26_4.html */
        sd $gp, 16($a0) /* Save gp to env[2],  *(long*)($a0+16) =gp */
        sd $s0, 24($a0) /* Save s0 to env[3],  *(long*)($a0+24)=s0 */
        sd $s1, 32($a0) /* Save s1 to env[4],  *(long*)($a0+32)=s1 */
        sd $s2, 40($a0) /* Save s2 to env[5],  *(long*)($a0+40)=s2 */
        sd $s3, 48($a0) /* Save s3 to env[6],  *(long*)($a0+48)=s3 */
        sd $s4, 56($a0) /* Save s4 to env[7],  *(long*)($a0+56)=s4 */
        sd $s5, 64($a0) /* Save s5 to env[8],  *(long*)($a0+64)=s5 */
        sd $s6, 72($a0) /* Save s6 to env[9],  *(long*)($a0+72)=s6 */
        sd $s7, 80($a0) /* Save s7 to env[10], *(long*)($a0+80)=s7 */
        sd $fp, 88($a0) /* Save fp to env[11], *(long*)($a0+88) =fp */
#if !defined(__mips_soft_float)
        sdc1 $f24, JB_F24 * 8($a0)
        sdc1 $f25, JB_F25 * 8($a0)
        sdc1 $f26, JB_F26 * 8($a0)
        sdc1 $f27, JB_F27 * 8($a0)
        sdc1 $f28, JB_F28 * 8($a0)
        sdc1 $f29, JB_F29 * 8($a0)
        sdc1 $f30, JB_F30 * 8($a0)
        sdc1 $f31, JB_F31 * 8($a0)
#endif
        li $v0, 0       /* Set return value to 0 */
        jr $ra          /* Return */

    	.size _st_md_cxt_save, .-_st_md_cxt_save

    /****************************************************************/

    	/* _st_md_cxt_restore(__jmp_buf env, int val) */
    	.globl _st_md_cxt_restore
    	.type _st_md_cxt_restore, %function
    	.align 2
    _st_md_cxt_restore:
        ld $sp,  0($a0) /* Load sp from env[0],  sp=*(long*)($a0+ 0)  */
        ld $ra,  8($a0) /* Load sp from env[1],  ra=*(long*)($a0+ 8), the saved return address */
        ld $gp, 16($a0) /* Load sp from env[2],  gp=*(long*)($a0+16)  */
        ld $s0, 24($a0) /* Load sp from env[3],  s0=*(long*)($a0+24) */
        ld $s1, 32($a0) /* Load sp from env[4],  s1=*(long*)($a0+32) */
        ld $s2, 40($a0) /* Load sp from env[5],  s2=*(long*)($a0+40) */
        ld $s3, 48($a0) /* Load sp from env[6],  s3=*(long*)($a0+48) */
        ld $s4, 56($a0) /* Load sp from env[7],  s4=*(long*)($a0+56) */
        ld $s5, 64($a0) /* Load sp from env[8],  s5=*(long*)($a0+64) */
        ld $s6, 72($a0) /* Load sp from env[9],  s6=*(long*)($a0+72) */
        ld $s7, 80($a0) /* Load sp from env[10], s7=*(long*)($a0+80) */
        ld $fp, 88($a0) /* Load sp from env[2],  fp=*(long*)($a0+88)  */
#if !defined(__mips_soft_float)
        ldc1 $f24, JB_F24 * 8($a0)
        ldc1 $f25, JB_F25 * 8($a0)
        ldc1 $f26, JB_F26 * 8($a0)
        ldc1 $f27, JB_F27 * 8($a0)
        ldc1 $f28, JB_F28 * 8($a0)
        ldc1 $f29, JB_F29 * 8($a0)
        ldc1 $f30, JB_F30 * 8($a0)
        ldc1 $f31, JB_F31 * 8($a0)
#endif
        li $v0, 1       /* Set return value to 1 */
        jr $ra          /* Return to the saved return address */

    	.size _st_md_cxt_restore, .-_st_md_cxt_restore

    /****************************************************************/

    /*
     * void _st_md_thread_start(void), the entry of a new thread, never returns.
     * MD_INIT_THREAD_ENTRY in md.h points the return address of the new thread's jmpbuf here, its
     * SP at a 16-byte boundary, and its fp at 0. So the first _st_md_cxt_restore of the thread
     * jumps here on the new stack, with none of its creator's frames. The restore jumps by $ra and
     * leaves $t9 and $gp to the creator, so the entry finds its own address with bal, computes its
     * own $gp from it, and calls _st_thread_main through $t9, as PIC code expects. The undefined
     * return address ends DWARF unwinds here, and the null fp and ra end frame-pointer walks.
     */
    	.globl _st_md_thread_start
    	.type _st_md_thread_start, %function
    	.align 2
    _st_md_thread_start:
    	.cfi_startproc
    	.cfi_undefined $ra
    	/*
    	 * Explicit relocations, not the .cpsetup and dla macros, because the file is assembled
    	 * without -fPIC, which turns those macros into absolute addresses, but also goes into
    	 * the shared library.
    	 */
    	.set push
    	.set noreorder
    	.set nomacro
        bal 1f                                      /* ra = 1f, the address of the next label */
        nop
    1:  lui $gp, %hi(%neg(%gp_rel(1b)))             /* gp = the GOT pointer of this module, ... */
        daddu $gp, $gp, $ra                         /* ... from ra, the run-time address of 1b */
        daddiu $gp, $gp, %lo(%neg(%gp_rel(1b)))
        ld $t9, %call16(_st_thread_main)($gp)       /* PIC callees compute their gp from t9 */
        move $fp, $zero
        move $ra, $zero
        jalr $t9
        nop
        /* _st_thread_main calls st_thread_exit, which never returns. */
        break
    	.set pop
    	.cfi_endproc
    	.size _st_md_thread_start, .-_st_md_thread_start

    /****************************************************************/






#elif defined(__mips__)

    /****************************************************************/
    /* For MIPS32, see https://s3-eu-west-1.amazonaws.com/downloads-mips/documents/MD00565-2B-MIPS32-QRC-01.01.pdf */

    /*
     * Internal __jmp_buf layout
     */
    #define JB_SP  0    /* Stack pointer */
    #define JB_RA  1    /* Return address */
    #define JB_GP  2    /* Global pointer */
    #define JB_S0  3    /* S0-S7, Saved temporaries */
    #define JB_S1  4    /* S0-S7, Saved temporaries */
    #define JB_S2  5    /* S0-S7, Saved temporaries */
    #define JB_S3  6    /* S0-S7, Saved temporaries */
    #define JB_S4  7    /* S0-S7, Saved temporaries */
    #define JB_S5  8    /* S0-S7, Saved temporaries */
    #define JB_S6  9    /* S0-S7, Saved temporaries */
    #define JB_S7  10   /* S0-S7, Saved temporaries */
    #define JB_FP  11   /* FP/S8 Frame pointer */
    /*
     * F20-F30 even, the callee-saved FP registers of o32, as doubles in two slots each. md.h aligns
     * the jmpbuf to 8 bytes for sdc1. Saving the even registers as doubles is right for every o32 FP
     * mode: with -mfp32 each holds the pair F20/F21 to F30/F31, and with -mfpxx or -mfp64 only the
     * even registers are callee-saved.
     */
    #define JB_F20 12
    #define JB_F22 14
    #define JB_F24 16
    #define JB_F26 18
    #define JB_F28 20
    #define JB_F30 22

    	.file "md_linux.S"
    	.text

    	/* _st_md_cxt_save(__jmp_buf env) */ /* The env is $a0, https://en.wikipedia.org/wiki/MIPS_architecture#Calling_conventions */
    	.globl _st_md_cxt_save
    	.type _st_md_cxt_save, %function
    	.align 2
    _st_md_cxt_save:
        sw $sp, 0($a0)  /* Save sp to env[0],  *(long*)($a0+0) =sp */
        sw $ra, 4($a0)  /* Save ra to env[1],  *(long*)($a0+4)=ra, the return address, https://chortle.ccsu.edu/AssemblyTutorial/Chapter-26/ass26_4.html */
        sw $gp, 8($a0)  /* Save gp to env[2],  *(long*)($a0+8) =gp */
        sw $s0, 12($a0) /* Save s0 to env[3],  *(long*)($a0+12)=s0 */
        sw $s1, 16($a0) /* Save s1 to env[4],  *(long*)($a0+16)=s1 */
        sw $s2, 20($a0) /* Save s2 to env[5],  *(long*)($a0+20)=s2 */
        sw $s3, 24($a0) /* Save s3 to env[6],  *(long*)($a0+24)=s3 */
        sw $s4, 28($a0) /* Save s4 to env[7],  *(long*)($a0+28)=s4 */
        sw $s5, 32($a0) /* Save s5 to env[8],  *(long*)($a0+32)=s5 */
        sw $s6, 36($a0) /* Save s6 to env[9],  *(long*)($a0+36)=s6 */
        sw $s7, 40($a0) /* Save s7 to env[10], *(long*)($a0+40)=s7 */
        sw $fp, 44($a0) /* Save fp to env[11], *(long*)($a0+44) =fp */
#if !defined(__mips_soft_float)
        sdc1 $f20, JB_F20 * 4($a0)
        sdc1 $f22, JB_F22 * 4($a0)
        sdc1 $f24, JB_F24 * 4($a0)
        sdc1 $f26, JB_F26 * 4($a0)
        sdc1 $f28, JB_F28 * 4($a0)
        sdc1 $f30, JB_F30 * 4($a0)
#endif
        li $v0, 0       /* Set return value to 0 */
        jr $ra          /* Return */

    	.size _st_md_cxt_save, .-_st_md_cxt_save

    /****************************************************************/

    	/* _st_md_cxt_restore(__jmp_buf env, int val) */
    	.globl _st_md_cxt_restore
    	.type _st_md_cxt_restore, %function
    	.align 2
    _st_md_cxt_restore:
        lw $sp, 0($a0)  /* Load sp from env[0],  sp=*(long*)($a0+0)  */
        lw $ra, 4($a0)  /* Load sp from env[1],  ra=*(long*)($a0+4), the saved return address */
        lw $gp, 8($a0)  /* Load sp from env[2],  gp=*(long*)($a0+8)  */
        lw $s0, 12($a0) /* Load sp from env[3],  s0=*(long*)($a0+12) */
        lw $s1, 16($a0) /* Load sp from env[4],  s1=*(long*)($a0+16) */
        lw $s2, 20($a0) /* Load sp from env[5],  s2=*(long*)($a0+20) */
        lw $s3, 24($a0) /* Load sp from env[6],  s3=*(long*)($a0+24) */
        lw $s4, 28($a0) /* Load sp from env[7],  s4=*(long*)($a0+28) */
        lw $s5, 32($a0) /* Load sp from env[8],  s5=*(long*)($a0+32) */
        lw $s6, 36($a0) /* Load sp from env[9],  s6=*(long*)($a0+36) */
        lw $s7, 40($a0) /* Load sp from env[10], s7=*(long*)($a0+40) */
        lw $fp, 44($a0) /* Load sp from env[2],  fp=*(long*)($a0+44)  */
#if !defined(__mips_soft_float)
        ldc1 $f20, JB_F20 * 4($a0)
        ldc1 $f22, JB_F22 * 4($a0)
        ldc1 $f24, JB_F24 * 4($a0)
        ldc1 $f26, JB_F26 * 4($a0)
        ldc1 $f28, JB_F28 * 4($a0)
        ldc1 $f30, JB_F30 * 4($a0)
#endif
        li $v0, 1       /* Set return value to 1 */
        jr $ra          /* Return to the saved return address */

    	.size _st_md_cxt_restore, .-_st_md_cxt_restore

    /****************************************************************/

    /*
     * void _st_md_thread_start(void), the entry of a new thread, never returns.
     * MD_INIT_THREAD_ENTRY in md.h points the return address of the new thread's jmpbuf here, its
     * SP at an 8-byte boundary, and its fp at 0. So the first _st_md_cxt_restore of the thread
     * jumps here on the new stack, with none of its creator's frames. The restore jumps by $ra and
     * leaves $t9 and $gp to the creator, so the entry finds its own address with bal, computes its
     * own $gp from it, and calls _st_thread_main through $t9, as PIC code expects. The o32 caller
     * reserves 16 bytes below the SP for the callee to save its four argument registers. The
     * undefined return address ends DWARF unwinds here, and the null fp and ra end frame-pointer
     * walks.
     */
    	.globl _st_md_thread_start
    	.type _st_md_thread_start, %function
    	.align 2
    _st_md_thread_start:
    	.cfi_startproc
    	.cfi_undefined $ra
    	/*
    	 * Explicit relocations, not the .cpload macro, because the file is assembled without
    	 * -fPIC, which turns .cpload into the absolute address __gnu_local_gp, but also goes into
    	 * the shared library.
    	 */
    	.set push
    	.set noreorder
    	.set nomacro
        bal 1f                                      /* ra = 1f, the address of the next label */
        nop
    1:  lui $gp, %hi(_gp_disp)                      /* gp = the GOT pointer of this module, ... */
        addiu $gp, $gp, %lo(_gp_disp)
        addu $gp, $gp, $ra                         /* ... from ra, the run-time address of 1b */
        lw $t9, %call16(_st_thread_main)($gp)      /* PIC callees compute their gp from t9 */
        addiu $sp, $sp, -16                        /* The argument save area of the callee */
    	.cfi_adjust_cfa_offset 16
        move $fp, $zero
        move $ra, $zero
        jalr $t9
        nop
        /* _st_thread_main calls st_thread_exit, which never returns. */
        break
    	.set pop
    	.cfi_endproc
    	.size _st_md_thread_start, .-_st_md_thread_start

    /****************************************************************/






#elif defined(__loongarch64)

    /****************************************************************/

    /*
     * Internal __jmp_buf layout
     */
    #define JB_SP  0    /* R3, SP, Stack pointer */
    #define JB_RA  1    /* R1, RA, Return address */
    #define JB_FP  2    /* FP/R22 Frame pointer */
    #define JB_S0  3    /* R23-R31, S0-S8, Subroutine register variable */
    #define JB_S1  4    /* R23-R31, S0-S8, Subroutine register variable */
    #define JB_S2  5    /* R23-R31, S0-S8, Subroutine register variable */
    #define JB_S3  6    /* R23-R31, S0-S8, Subroutine register variable */
    #define JB_S4  7    /* R23-R31, S0-S8, Subroutine register variable */
    #define JB_S5  8    /* R23-R31, S0-S8, Subroutine register variable */
    #define JB_S6  9    /* R23-R31, S0-S8, Subroutine register variable */
    #define JB_S7  10   /* R23-R31, S0-S8, Subroutine register variable */
    #define JB_S8  11   /* R23-R31, S0-S8, Subroutine register variable */
    #define JB_F24 12   /* F24-F31, FS0-FS7, callee-saved FP registers */
    #define JB_F25 13
    #define JB_F26 14
    #define JB_F27 15
    #define JB_F28 16
    #define JB_F29 17
    #define JB_F30 18
    #define JB_F31 19

    /* Save F24-F31 as doubles with a 64-bit FPU, their low 32 bits with a 32-bit one, and nothing with soft float. */
    #if defined(__loongarch_frlen) && __loongarch_frlen >= 64
        #define FP_SAVE fst.d
        #define FP_LOAD fld.d
    #elif defined(__loongarch_frlen) && __loongarch_frlen == 32
        #define FP_SAVE fst.s
        #define FP_LOAD fld.s
    #endif

    	.file "md_linux.S"
    	.text

    	/* _st_md_cxt_save(__jmp_buf env) */ /* The env is $r4, https://github.com/ossrs/state-threads/issues/24#porting */
    	.globl _st_md_cxt_save
    	.type _st_md_cxt_save, %function
    	.align 2
    _st_md_cxt_save:
        st.d	$r3, $r4, 0           /* Save sp to env[0],  *(long*)($r4+0) = sp */
        st.d	$r1, $r4, 8           /* Save ra to env[1],  *(long*)($r4+8) = r1 */
        st.d	$r22, $r4, 16         /* Save fp to env[2],  *(long*)($r4+16) = r22 */
        st.d	$r23, $r4, 24         /* Save r23 to env[3],  *(long*)($r4+24) = r23 */
        st.d	$r24, $r4, 32         /* Save r24 to env[4],  *(long*)($r4+32) = r24 */
        st.d	$r25, $r4, 40         /* Save r25 to env[5],  *(long*)($r4+40) = r25 */
        st.d	$r26, $r4, 48         /* Save r26 to env[6],  *(long*)($r4+48) = r26 */
        st.d	$r27, $r4, 56         /* Save r27 to env[7],  *(long*)($r4+56) = r27 */
        st.d	$r28, $r4, 64         /* Save r28 to env[8],  *(long*)($r4+64) = r28 */
        st.d	$r29, $r4, 72         /* Save r29 to env[9],  *(long*)($r4+72) = r29 */
        st.d	$r30, $r4, 80         /* Save r30 to env[10],  *(long*)($r4+80) = r30 */
        st.d	$r31, $r4, 88         /* Save r31 to env[11],  *(long*)($r4+88) = r31 */
#if defined(FP_SAVE)
        FP_SAVE	$f24, $r4, JB_F24 * 8 /* Save f24-f31 to env[12]-env[19] */
        FP_SAVE	$f25, $r4, JB_F25 * 8
        FP_SAVE	$f26, $r4, JB_F26 * 8
        FP_SAVE	$f27, $r4, JB_F27 * 8
        FP_SAVE	$f28, $r4, JB_F28 * 8
        FP_SAVE	$f29, $r4, JB_F29 * 8
        FP_SAVE	$f30, $r4, JB_F30 * 8
        FP_SAVE	$f31, $r4, JB_F31 * 8
#endif
        addi.w	$r12, $r0, 0          /* Set return value to 0 */
        move    $r4, $r12             /* Set return value to 0 */
        jirl	$r0, $r1, 0           /* Return */

    	.size _st_md_cxt_save, .-_st_md_cxt_save

    /****************************************************************/

    	/* _st_md_cxt_restore(__jmp_buf env, int val) */
    	.globl _st_md_cxt_restore
    	.type _st_md_cxt_restore, %function
    	.align 2
    _st_md_cxt_restore:
        ld.d	$r3, $r4, 0          /* Load sp from env[0],  sp=*(long*)($r4+0) */
        ld.d	$r1, $r4, 8          /* Load ra from env[1],  r1=*(long*)($r4+8) */
        ld.d	$r22, $r4, 16        /* Load fp from env[2],  r22=*(long*)($r4+16) */
        ld.d	$r23, $r4, 24        /* Load r23 from env[3],  r23=*(long*)($r4+24) */
        ld.d	$r24, $r4, 32        /* Load r24 from env[4],  r24=*(long*)($r4+32) */
        ld.d	$r25, $r4, 40        /* Load r25 from env[5],  r25=*(long*)($r4+40) */
        ld.d	$r26, $r4, 48        /* Load r26 from env[6],  r26=*(long*)($r4+48) */
        ld.d	$r27, $r4, 56        /* Load r27 from env[7],  r27=*(long*)($r4+56) */
        ld.d	$r28, $r4, 64        /* Load r28 from env[8],  r28=*(long*)($r4+64) */
        ld.d	$r29, $r4, 72        /* Load r29 from env[9],  r29=*(long*)($r4+72) */
        ld.d	$r30, $r4, 80        /* Load r30 from env[10],  r30=*(long*)($r4+80) */
        ld.d	$r31, $r4, 88        /* Load r31 from env[11],  r31=*(long*)($r4+88) */
#if defined(FP_LOAD)
        FP_LOAD	$f24, $r4, JB_F24 * 8 /* Load f24-f31 from env[12]-env[19] */
        FP_LOAD	$f25, $r4, JB_F25 * 8
        FP_LOAD	$f26, $r4, JB_F26 * 8
        FP_LOAD	$f27, $r4, JB_F27 * 8
        FP_LOAD	$f28, $r4, JB_F28 * 8
        FP_LOAD	$f29, $r4, JB_F29 * 8
        FP_LOAD	$f30, $r4, JB_F30 * 8
        FP_LOAD	$f31, $r4, JB_F31 * 8
#endif
        addi.w	$r12, $r0, 1         /* Set return value to 1 */
        move    $r4, $r12            /* Set return value to 1 */
        jirl	$r0, $r1, 0          /* Return to the saved return address */

    	.size _st_md_cxt_restore, .-_st_md_cxt_restore

    /****************************************************************/

    /*
     * void _st_md_thread_start(void), the entry of a new thread, never returns.
     * MD_INIT_THREAD_ENTRY in md.h points the return address of the new thread's jmpbuf here, its
     * SP at a 16-byte boundary, and its fp at 0. So the first _st_md_cxt_restore of the thread
     * jumps here on the new stack, with none of its creator's frames. The undefined return
     * address ends DWARF unwinds here, and the null fp and ra end frame-pointer walks.
     */
    	.globl _st_md_thread_start
    	.type _st_md_thread_start, %function
    	.align 2
    _st_md_thread_start:
    	.cfi_startproc
    	.cfi_undefined 1         /* ra, $r1 */
        move    $r22, $r0            /* fp = 0 */
        move    $r1, $r0             /* ra = 0 */
        bl      _st_thread_main
        /* _st_thread_main calls st_thread_exit, which never returns. */
        break   0
    	.cfi_endproc
    	.size _st_md_thread_start, .-_st_md_thread_start

    /****************************************************************/

#endif

#if defined(__linux__) && defined(__ELF__)
.section .note.GNU-stack,""
#endif

#endif
