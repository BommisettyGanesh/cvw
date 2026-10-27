// =============================================================================
// Test: subword_access_stress.S
// Purpose: Signal-level verification of byte and halfword transfers:
//          1. Byte writes at byte lanes 0, 1, 2, 3 (stresses HWSTRB=0001, 0010, 0100, 1000)
//          2. Halfword writes at lanes 0-1 and 2-3 (stresses HWSTRB=0011, 1100)
//          3. Sign-extension vs Zero-extension: lb/lbu, lh/lhu
//          4. Read-after-write data integrity across all lanes
// =============================================================================

    .section .text.init
    .globl rvtest_entry_point
    .globl tohost

rvtest_entry_point:
    li sp, 0x80007ff0
    li s0, 0x80002000    // Scratch RAM location

    // -------------------------------------------------------------------------
    // 1. Initialize 32-bit word with 0x00000000
    // -------------------------------------------------------------------------
    sw zero, 0(s0)

    // -------------------------------------------------------------------------
    // 2. Individual Byte writes (sb) at offsets 0, 1, 2, 3
    // -------------------------------------------------------------------------
    li t1, 0x12
    sb t1, 0(s0)         // Byte lane 0

    li t2, 0x34
    sb t2, 1(s0)         // Byte lane 1

    li t3, 0x56
    sb t3, 2(s0)         // Byte lane 2

    li t4, 0x78
    sb t4, 3(s0)         // Byte lane 3

    // Verify word reconstructed as 0x78563412 (Little-Endian)
    lw a1, 0(s0)
    li a2, 0x78563412
    bne a1, a2, fail_1

    // -------------------------------------------------------------------------
    // 3. Halfword writes (sh) at offsets 0 and 2
    // -------------------------------------------------------------------------
    li t1, 0xFEED
    sh t1, 0(s0)         // Halfword lane 0-1

    li t2, 0xBEEF
    sh t2, 2(s0)         // Halfword lane 2-3

    // Verify full word read is 0xBEEFFEED
    lw a1, 0(s0)
    li a2, 0xBEEFFEED
    bne a1, a2, fail_2

    // -------------------------------------------------------------------------
    // 4. Test Sign-extension (lb, lh) vs Zero-extension (lbu, lhu)
    // -------------------------------------------------------------------------
    // s0 points to 0xBEEFFEED:
    // byte 0 = 0xED (negative, bit 7=1)
    // byte 1 = 0xFE (negative, bit 7=1)
    // halfword 0 = 0xFEED (negative, bit 15=1)

    // Unsigned byte load: should be 0x000000ED
    lbu a1, 0(s0)
    li  a2, 0x000000ED
    bne a1, a2, fail_3

    // Signed byte load: should be 0xFFFFFFED
    lb  a1, 0(s0)
    li  a2, 0xFFFFFFED
    bne a1, a2, fail_4

    // Unsigned halfword load: should be 0x0000FEED
    lhu a1, 0(s0)
    li  a2, 0x0000FEED
    bne a1, a2, fail_5

    // Signed halfword load: should be 0xFFFFFEED
    lh  a1, 0(s0)
    li  a2, 0xFFFFFEED
    bne a1, a2, fail_6

    // -------------------------------------------------------------------------
    // All Subword Tests Passed!
    // -------------------------------------------------------------------------
    li a0, 1
    la t0, tohost
    sw a0, 0(t0)
pass_loop:
    j pass_loop

fail_1:
    li a0, 601
    j fail_exit
fail_2:
    li a0, 602
    j fail_exit
fail_3:
    li a0, 603
    j fail_exit
fail_4:
    li a0, 604
    j fail_exit
fail_5:
    li a0, 605
    j fail_exit
fail_6:
    li a0, 606
    j fail_exit

fail_exit:
    slli a0, a0, 1
    ori a0, a0, 1
    la t0, tohost
    sw a0, 0(t0)
fail_loop:
    j fail_loop

    .section .tohost, "aw", @progbits
    .align 4
tohost:
    .word 0
    .word 0
