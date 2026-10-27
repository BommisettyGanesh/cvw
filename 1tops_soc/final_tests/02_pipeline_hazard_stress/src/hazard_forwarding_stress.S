// =============================================================================
// Test: hazard_forwarding_stress.S
// Purpose: Signal-level verification of all data hazard and forwarding paths:
//          1. EX -> EX Forwarding (rs1 and rs2)
//          2. MEM -> EX Forwarding (rs1 and rs2)
//          3. Load-Use Hazard Stall (1 cycle bubble + forward)
//          4. Load-to-Store Forwarding
//          5. Deep Dependency Chains (3-stage cumulative accumulation)
// =============================================================================

    .section .text.init
    .globl rvtest_entry_point
    .globl tohost

rvtest_entry_point:
    li sp, 0x80007ff0

    // -------------------------------------------------------------------------
    // Test 1: EX -> EX Forwarding on rs1 and rs2
    // -------------------------------------------------------------------------
    li a0, 10
    li a1, 20
    add a2, a0, a1       // a2 = 30 (computed in EX stage)
    add a3, a2, a2       // a3 = 30 + 30 = 60 (requires EX->EX on both rs1 and rs2!)
    li t0, 60
    bne a3, t0, fail_1

    // -------------------------------------------------------------------------
    // Test 2: MEM -> EX Forwarding on rs1 and rs2
    // -------------------------------------------------------------------------
    li a0, 5
    li a1, 15
    add a2, a0, a1       // a2 = 20
    nop                  // puts a2 into MEM stage
    add a3, a2, a2       // requires MEM->EX on both rs1 and rs2
    li t0, 40
    bne a3, t0, fail_2

    // -------------------------------------------------------------------------
    // Test 3: Cumulative 3-stage dependency chain
    // -------------------------------------------------------------------------
    li t1, 1
    add t1, t1, t1       // 2
    add t1, t1, t1       // 4
    add t1, t1, t1       // 8
    add t1, t1, t1       // 16
    add t1, t1, t1       // 32
    li t0, 32
    bne t1, t0, fail_3

    // -------------------------------------------------------------------------
    // Test 4: Load-Use Hazard (Stall 1 cycle + Forward)
    // -------------------------------------------------------------------------
    la s0, scratchpad
    li t2, 0x12345678
    sw t2, 0(s0)
    lw t3, 0(s0)         // Load into t3
    addi t4, t3, 1       // IMMEDIATELY uses t3: MUST trigger load-use stall!
    li t0, 0x12345679
    bne t4, t0, fail_4

    // -------------------------------------------------------------------------
    // Test 5: Load-to-Store Forwarding (Store immediately uses Load output)
    // -------------------------------------------------------------------------
    lw t5, 0(s0)
    sw t5, 4(s0)         // Store uses t5 from MEM stage
    lw t6, 4(s0)
    bne t6, t2, fail_5

    // -------------------------------------------------------------------------
    // Test Passed
    // -------------------------------------------------------------------------
    li a0, 1
    la t0, tohost
    sw a0, 0(t0)
pass_loop:
    j pass_loop

fail_1:
    li a0, 101
    j fail_exit
fail_2:
    li a0, 102
    j fail_exit
fail_3:
    li a0, 103
    j fail_exit
fail_4:
    li a0, 104
    j fail_exit
fail_5:
    li a0, 105
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

    .section .data
    .align 4
scratchpad:
    .word 0
    .word 0
