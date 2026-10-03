/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2013-2026 The SRS Authors */

/*
 * Native Windows x64 (MSVC) context switch stub, so ST links. It aborts until
 * the context switch is ported to md_win64.asm.
 */

#include <stdio.h>
#include <stdlib.h>
#include "common.h"

int _st_md_cxt_save(_st_jmp_buf_t env)
{
    (void) env;
    fprintf(stderr, "ST: _st_md_cxt_save, context switch not ported to Windows yet\n");
    abort();
}

void _st_md_cxt_restore(_st_jmp_buf_t env, int val)
{
    (void) env;
    (void) val;
    fprintf(stderr, "ST: _st_md_cxt_restore, context switch not ported to Windows yet\n");
    abort();
}
