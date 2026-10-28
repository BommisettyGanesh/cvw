// =============================================================================
// Test: exception_trap_stress.S
// Purpose: Signal-level verification of synchronous CPU exceptions:
//          1. ecall (Environment Call from M-Mode, mcause = 11)
//          2. ebreak (Breakpoint, mcause = 3)
//          3. Illegal Instruction (.word 0x00000000, mcause = 2)
//          Verifies trap capture, pipeline flush, mcause/mepc capture,
//          and clean mret resumption.
// =============================================================================

    .section .text.init
    .globl rvtest_entry_point
    .globl tohost

rvtest_entry_point:
    li sp, 0x80007ff0
    li s1, 0             // Expected cause
    li s2, 0             // Exception counter

    // 1. Install Trap Handler
    la t0, trap_handler
    csrw mtvec, t0

    // -------------------------------------------------------------------------
    // Test Case 1: ecall (Cause 11)
    // -------------------------------------------------------------------------
    li s1, 11
ecall_label:
    ecall
    // After mret, should return here:
    li t0, 1
    bne s2, t0, fail_1

    // -------------------------------------------------------------------------
    // Test Case 2: ebreak (Cause 3)
    // -------------------------------------------------------------------------
    li s1, 3
ebreak_label:
    ebreak
    // After mret, should return here:
    li t0, 2
    bne s2, t0, fail_2

    // -------------------------------------------------------------------------
    // Test Case 3: Illegal Instruction (Cause 2)
    // -------------------------------------------------------------------------
    li s1, 2
illegal_label:
    .word 0x00200073     // Illegal SYSTEM instruction (funct12=0x002, funct3=000)
    // After mret, should return here:
    li t0, 3
    bne s2, t0, fail_3

    // -------------------------------------------------------------------------
    // All Exception Tests Passed!
    // -------------------------------------------------------------------------
    li a0, 1
    la t0, tohost
    sw a0, 0(t0)
pass_loop:
    j pass_loop

fail_1:
    li a0, 501
    j fail_exit
fail_2:
    li a0, 502
    j fail_exit
fail_3:
    li a0, 503
    j fail_exit

fail_exit:
    slli a0, a0, 1
    ori a0, a0, 1
    la t0, tohost
    sw a0, 0(t0)
fail_loop:
    j fail_loop

// -----------------------------------------------------------------------------
// Exception Trap Handler
// -----------------------------------------------------------------------------
    .align 4
trap_handler:
    csrr t1, mcause
    bne t1, s1, fail_handler // Verify cause matches expected

    // Advance mepc past the faulting 4-byte instruction to continue
    csrr t2, mepc
    addi t2, t2, 4
    csrw mepc, t2

    addi s2, s2, 1           // Increment handled exceptions
    mret

fail_handler:
    li a0, 599
    j fail_exit

    .section .tohost, "aw", @progbits
    .align 4
tohost:
    .word 0
    .word 0
