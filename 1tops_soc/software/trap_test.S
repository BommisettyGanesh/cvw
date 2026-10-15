# trap_test.S - Live Software Interrupt Trap Verification
.section .text
.globl _start

_start:
    # 1. Initialize trap vector to handle_trap (Direct Mode)
    la    t0, handle_trap
    csrw  mtvec, t0

    # 2. Clear Mailbox in Data RAM (0x80002010 = 0)
    lui   s0, 0x80002
    sw    zero, 0x010(s0)

    # 3. Enable Machine Software Interrupts (mie.MSIE = bit 3)
    li    t1, 0x08
    csrs  mie, t1

    # 4. Enable Global Interrupts (mstatus.MIE = bit 3)
    csrsi mstatus, 0x08

wait_loop:
    # 5. Wait For Interrupt (or tight loop if WFI is NOP)
    wfi
    j     wait_loop

# -------------------------------------------------------------
# Trap Handler
# -------------------------------------------------------------
.align 4
handle_trap:
    # Read mcause to confirm it is Machine Software Interrupt (cause = 3)
    csrr  t2, mcause
    li    t3, 3
    bne   t2, t3, trap_exit

    # Increment Mailbox at 0x80002010 (indicates handler executed)
    lw    t4, 0x010(s0)
    addi  t4, t4, 1
    sw    t4, 0x010(s0)

    # Clear MSIP in CLINT (Address 0x02000000 = 0) to acknowledge interrupt
    lui   t5, 0x02000
    sw    zero, 0x000(t5)

trap_exit:
    mret

