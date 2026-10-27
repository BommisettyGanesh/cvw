.section .text.init
.globl _start
.type _start, @function

_start:
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop

    // Initialize stack pointer
    la      sp, __stack

    // Initialize registers (preserving sp and gp)
    li x1, 0
    li x4, 0
    li x5, 0
    li x6, 0
    li x7, 0
    li x8, 0
    li x9, 0
    li x10, 0
    li x11, 0
    li x12, 0
    li x13, 0
    li x14, 0
    li x15, 0
    li x16, 0
    li x17, 0
    li x18, 0
    li x19, 0
    li x20, 0
    li x21, 0
    li x22, 0
    li x23, 0
    li x24, 0
    li x25, 0
    li x26, 0
    li x27, 0
    li x28, 0
    li x29, 0
    li x30, 0
    li x31, 0

    // Clear BSS section
    la      t0, __bss_start
    la      t1, __bss_end
bss_loop:
    bgeu    t0, t1, bss_done
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       bss_loop
bss_done:

    // Call main()
    call    main

    // If main returns, write return code to 0x80001004 (tohost)
    li      t0, 0x80001004
    sw      a0, 0(t0)

1:  j       1b

.size _start, . - _start
