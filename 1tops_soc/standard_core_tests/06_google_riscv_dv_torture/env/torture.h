#ifndef _TORTURE_H
#define _TORTURE_H

#define TOHOST_ADDR   0x80001004
#define CONSOLE_ADDR  0x80001000

#define TORTURE_INIT \
    .section .text.init; \
    .globl _start; \
    .type _start, @function; \
_start: \
    .option push; \
    .option norelax; \
    la gp, __global_pointer$; \
    .option pop; \
    la sp, __stack; \
    la t0, trap_entry; \
    csrw mtvec, t0; \
    li x1, 0;  li x4, 0;  li x5, 0;  li x6, 0; \
    li x7, 0;  li x8, 0;  li x9, 0;  li x10, 0; \
    li x11, 0; li x12, 0; li x13, 0; li x14, 0; \
    li x15, 0; li x16, 0; li x17, 0; li x18, 0; \
    li x19, 0; li x20, 0; li x21, 0; li x22, 0; \
    li x23, 0; li x24, 0; li x25, 0; li x26, 0; \
    li x27, 0; li x28, 0; li x29, 0; li x30, 0; \
    li x31, 0;

#define TORTURE_PASS \
    li t0, TOHOST_ADDR; \
    li t1, 1; \
    sw t1, 0(t0); \
    la t0, tohost; \
    sw t1, 0(t0); \
1:  j 1b

#define TORTURE_FAIL(test_id) \
    li t0, TOHOST_ADDR; \
    li t1, ((test_id << 1) | 1); \
    sw t1, 0(t0); \
    la t0, tohost; \
    sw t1, 0(t0); \
1:  j 1b

#define CHECK_VAL(reg, expected, test_id) \
    li t0, expected; \
    bne reg, t0, 99f; \
    .section .text; \
    j 98f; \
99: TORTURE_FAIL(test_id); \
98:

#define TRAP_HANDLER \
    .section .text; \
    .align 4; \
trap_entry: \
    csrr t2, mcause; \
    TORTURE_FAIL(0xdead);

#define TOHOST_SECTION \
    .section .tohost, "aw", @progbits; \
    .align 6; \
    .globl tohost; \
tohost: \
    .word 0; \
    .align 6; \
    .globl fromhost; \
fromhost: \
    .word 0;

#endif
