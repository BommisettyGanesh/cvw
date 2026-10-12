.section .text
.globl _start

_start:
    # Load Data Memory base pointer (0x80002000)
    lui   s0, 0x80002
    
    # Read n from 1st Data Memory word (0x80002000)
    lw    s1, 0(s0)

    # Initialize result = 1 (s2 = result)
    li    s2, 1

    # If n <= 1, factorial is 1
    li    t0, 1
    ble   s1, t0, done

fact_loop:
    # Compute s2 = s2 * s1 using shift-and-add (pure RV32I)
    mv    t1, s2            # multiplicand
    mv    t2, s1            # multiplier
    li    s2, 0             # accumulator

mul_step:
    andi  t3, t2, 1
    beqz  t3, mul_skip_add
    add   s2, s2, t1
mul_skip_add:
    slli  t1, t1, 1
    srli  t2, t2, 1
    bnez  t2, mul_step

    # Decrement n and loop
    addi  s1, s1, -1
    li    t0, 1
    bgt   s1, t0, fact_loop

done:
    # Write result to 2nd Data Memory word (0x80002004)
    sw    s2, 4(s0)

halt:
    j     halt
