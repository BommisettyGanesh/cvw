# trap_test.S - Live Software Interrupt Trap Verification
.section .text
.globl _start

_start:
    # 1. Write Boot Signature to Data RAM (0x80002000 = 0xAA)
    #    Proves that the CPU has successfully reset and started executing!
    lui   s0, 0x80002
    li    t0, 0xaa
    sw    t0, 0x000(s0)

    # 2. Clear Mailbox in Data RAM (0x80002010 = 0, 0x80002014 = 0)
    sw    zero, 0x010(s0)
    sw    zero, 0x014(s0)

    # 3. Initialize trap vector to handle_trap (Direct Mode)
    la    t0, handle_trap
    csrw  mtvec, t0

    # 4. Enable Machine Software Interrupts (mie.MSIE = bit 3)
    li    t1, 0x08
    csrs  mie, t1

    # 5. Enable Global Interrupts (mstatus.MIE = bit 3)
    csrsi mstatus, 0x08

    # 6. Write Ready Signature to Data RAM (0x80002000 = 0xBB)
    #    Proves interrupts are enabled and CPU is entering wait loop!
    li    t0, 0xbb
    sw    t0, 0x000(s0)

wait_loop:
    # 7. Wait loop
    wfi
    j     wait_loop

# -------------------------------------------------------------
# Trap Handler
# -------------------------------------------------------------
.align 4
handle_trap:
    # In RISC-V, Interrupt mcause has bit 31 set!
    # For Machine Software Interrupt, mcause = 0x80000003
    csrr  t2, mcause

    # Record the raw mcause in Data RAM at 0x80002014 for diagnostics
    lui   t0, 0x80002
    sw    t2, 0x014(t0)

    # Verify cause is Machine Software Interrupt (0x80000003)
    li    t3, 0x80000003
    bne   t2, t3, trap_exit

    # Increment Mailbox at 0x80002010 (indicates handler executed)
    lw    t4, 0x010(t0)
    addi  t4, t4, 1
    sw    t4, 0x010(t0)

    # Clear MSIP in CLINT (Address 0x02000000 = 0) to acknowledge interrupt
    lui   t5, 0x02000
    sw    zero, 0x000(t5)

trap_exit:
    mret
