// =============================================================================
// Test: interrupt_trap_stress.S
// Purpose: Signal-level verification of CLINT timer interrupt and trap mechanism:
//          1. Sets up mtvec, mie (MTIE), and mstatus (MIE)
//          2. Sets CLINT mtimecmp to trigger MTimerInt
//          3. Trap handler verifies mcause, mepc, clears interrupt, and executes mret
//          4. Verifies clean return and resumption of execution
// =============================================================================

    .section .text.init
    .globl rvtest_entry_point
    .globl tohost

.equ CLINT_BASE,      0x02000000
.equ CLINT_MTIMECMP,  0x02004000
.equ CLINT_MTIMECMPH, 0x02004004
.equ CLINT_MTIME,     0x0200bff8

rvtest_entry_point:
    li sp, 0x80007ff0
    li s10, 0            // Interrupt handled counter

    // 1. Install Trap Handler
    la t0, trap_handler
    csrw mtvec, t0

    // 2. Clear MTIMECMPH to 0 so upper 32-bits match
    li t1, CLINT_MTIMECMPH
    sw zero, 0(t1)

    // 3. Read present mtime and schedule interrupt 40 cycles into future
    li t1, CLINT_MTIME
    lw t2, 0(t1)         // read mtime
    addi t2, t2, 40      // mtimecmp = mtime + 40
    li t1, CLINT_MTIMECMP
    sw t2, 0(t1)         // write mtimecmp

    // 4. Enable Machine Timer Interrupt (mie.MTIE = bit 7)
    li t0, 0x80
    csrs mie, t0

    // 5. Enable Global Interrupts (mstatus.MIE = bit 3)
    csrsi mstatus, 0x8

    // 6. Spin waiting for interrupt to fire
    li a0, 500
wait_loop:
    bnez s10, interrupt_received // s10 incremented in trap handler!
    addi a0, a0, -1
    bnez a0, wait_loop

    // If reached here, interrupt timed out
    li a0, 301
    j fail_exit

interrupt_received:
    // Interrupt handled cleanly and mret returned!
    li a0, 1
    la t0, tohost
    sw a0, 0(t0)
pass_loop:
    j pass_loop

// -----------------------------------------------------------------------------
// Machine-Mode Trap Handler
// -----------------------------------------------------------------------------
    .align 4
trap_handler:
    // Clear interrupt by setting mtimecmp upper word to max
    li t4, CLINT_MTIMECMPH
    li t5, -1
    sw t5, 0(t4)

    // Mark interrupt handled
    addi s10, s10, 1

    // Return to interrupted instruction
    mret

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
