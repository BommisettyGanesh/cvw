#include "torture.h"

TORTURE_INIT

    /* =========================================================================
     * SECTION 1: Distance-1 Back-to-Back RAW Hazards (EX-to-EX Forwarding)
     * ========================================================================= */
    li x5, 10
    li x6, 20
    add x7, x5, x6      /* x7 = 30 */
    addi x8, x7, 5      /* x8 = 35 (RAW on x7, distance 1) */
    sub x9, x8, x5      /* x9 = 25 (RAW on x8, distance 1) */
    slli x10, x9, 2     /* x10 = 100 (RAW on x9, distance 1) */
    xor x11, x10, x6    /* x11 = 100 ^ 20 = 112 (RAW on x10, distance 1) */
    CHECK_VAL(x11, 112, 1)

    /* =========================================================================
     * SECTION 2: Distance-2 RAW Hazards (MEM-to-EX Forwarding)
     * ========================================================================= */
    li x12, 50
    addi x13, x12, 15   /* x13 = 65 */
    nop
    sub x14, x13, x12   /* x14 = 15 (RAW on x13, distance 2) */
    nop
    srai x15, x14, 1    /* x15 = 7 (RAW on x14, distance 2) */
    CHECK_VAL(x15, 7, 2)

    /* =========================================================================
     * SECTION 3: Distance-3 RAW Hazards (WB-to-EX Register Bypass)
     * ========================================================================= */
    li x16, 200
    addi x17, x16, 55   /* x17 = 255 */
    nop
    nop
    andi x18, x17, 0x0f /* x18 = 15 (RAW on x17, distance 3) */
    CHECK_VAL(x18, 15, 3)

    /* =========================================================================
     * SECTION 4: Multi-Register Dual-Operand Forwarding Chains
     * rs1 forwarded from EX, rs2 forwarded from MEM
     * ========================================================================= */
    li x19, 100
    li x20, 200
    add x21, x19, x20   /* x21 = 300 */
    sub x22, x20, x19   /* x22 = 100 */
    add x23, x22, x21   /* x23 = 100 + 300 = 400 (rs1 from EX, rs2 from MEM) */
    CHECK_VAL(x23, 400, 4)

    /* =========================================================================
     * SECTION 5: 32-Instruction Forwarding Ring Torture
     * ========================================================================= */
    li x1, 1
    addi x2, x1, 2
    addi x3, x2, 3
    addi x4, x3, 4
    addi x5, x4, 5
    addi x6, x5, 6
    addi x7, x6, 7
    addi x8, x7, 8
    addi x9, x8, 9
    addi x10, x9, 10
    addi x11, x10, 11
    addi x12, x11, 12
    addi x13, x12, 13
    addi x14, x13, 14
    addi x15, x14, 15
    addi x16, x15, 16
    addi x17, x16, 17
    addi x18, x17, 18
    addi x19, x18, 19
    addi x20, x19, 20
    addi x21, x20, 21
    addi x22, x21, 22
    addi x23, x22, 23
    addi x24, x23, 24
    addi x25, x24, 25
    addi x26, x25, 26
    addi x27, x26, 27
    addi x28, x27, 28
    addi x29, x28, 29
    addi x30, x29, 30
    addi x31, x30, 31
    CHECK_VAL(x31, 496, 5)

    TORTURE_PASS
TRAP_HANDLER
TOHOST_SECTION
