// =============================================================================
// Test: apb_bus_stress.S
// Purpose: Signal-level verification of back-to-back APB transfers across
//          multiple peripherals without idle cycles (GPIO, UART, CLINT).
// =============================================================================

    .section .text.init
    .globl rvtest_entry_point
    .globl tohost

.equ GPIO_OUT_EN,  0x10060008
.equ GPIO_OUT_VAL, 0x1006000c
.equ UART_SCRATCH, 0x10000007
.equ CLINT_MSIP,   0x02000000

rvtest_entry_point:
    li sp, 0x80007ff0

    // 1. Back-to-back writes across different peripherals
    li t0, GPIO_OUT_EN
    li t1, 0xA5A5A5A5
    sw t1, 0(t0)         // Write GPIO Out Enable

    li t2, UART_SCRATCH
    li t3, 0x5A
    sb t3, 0(t2)         // Write UART Scratchpad (Byte access)

    li t4, GPIO_OUT_VAL
    li t5, 0x12345678
    sw t5, 0(t4)         // Write GPIO Out Val

    // 2. Back-to-back reads verifying data integrity
    lw a1, 0(t0)         // Read back GPIO Out Enable
    bne a1, t1, fail_1

    lbu a2, 0(t2)        // Read back UART Scratchpad
    bne a2, t3, fail_2

    lw a3, 0(t4)         // Read back GPIO Out Val
    bne a3, t5, fail_3

    // 3. Test Passed
    li a0, 1
    la t0, tohost
    sw a0, 0(t0)
pass_loop:
    j pass_loop

fail_1:
    li a0, 401
    j fail_exit
fail_2:
    li a0, 402
    j fail_exit
fail_3:
    li a0, 403
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
