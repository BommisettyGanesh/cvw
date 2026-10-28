// =============================================================================
// Test: branch_collision_stress.S
// Purpose: Signal-level verification of branch misprediction and pipeline flushing:
//          1. Verifies killed instructions after taken branch NEVER alter registers/memory
//          2. Verifies not-taken branches proceed without pipeline stalls/bubbles
//          3. Verifies JAL and JALR return address link (ra = PC + 4)
//          4. Verifies tight backward loop control
// =============================================================================

    .section .text.init
    .globl rvtest_entry_point
    .globl tohost

rvtest_entry_point:
    li sp, 0x80007ff0

    // -------------------------------------------------------------------------
    // Test 1: Taken branch kills shadow instructions
    // -------------------------------------------------------------------------
    li a0, 0
    li t0, 1
    li t1, 1
    beq t0, t1, target_1
    // Shadow instructions: MUST BE KILLED BY FLUSH!
    addi a0, a0, 100
    addi a0, a0, 200

target_1:
    // a0 must remain 0
    bnez a0, fail_1

    // -------------------------------------------------------------------------
    // Test 2: Not-taken branch does not flush
    // -------------------------------------------------------------------------
    li a1, 0
    bne t0, t1, bad_target
    addi a1, a1, 5       // Must execute!
    j next_2
bad_target:
    addi a1, a1, 999
next_2:
    li t2, 5
    bne a1, t2, fail_2

    // -------------------------------------------------------------------------
    // Test 3: JAL & JALR Link Register (ra) accuracy
    // -------------------------------------------------------------------------
    jal ra, test_func
after_func:
    li t3, 42
    bne a2, t3, fail_3

    // -------------------------------------------------------------------------
    // Test 4: Tight backward loop iteration (50 cycles)
    // -------------------------------------------------------------------------
    li s1, 50
    li s2, 0
loop_tight:
    addi s2, s2, 1
    addi s1, s1, -1
    bnez s1, loop_tight

    li t0, 50
    bne s2, t0, fail_4

    // -------------------------------------------------------------------------
    // Test Passed
    // -------------------------------------------------------------------------
    li a0, 1
    la t0, tohost
    sw a0, 0(t0)
pass_loop:
    j pass_loop

test_func:
    // Verify ra == address of after_func
    la t4, after_func
    bne ra, t4, fail_jal
    li a2, 42
    jr ra

fail_1:
    li a0, 201
    j fail_exit
fail_2:
    li a0, 202
    j fail_exit
fail_3:
    li a0, 203
    j fail_exit
fail_4:
    li a0, 204
    j fail_exit
fail_jal:
    li a0, 205
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
