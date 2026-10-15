# profile_accel.S - Measures exact hardware latency of Accelerator
.section .text
.globl _start

_start:
    # Base pointer to CLINT mtime (0x0200_BFF8)
    lui   s0, 0x0200c
    # Base pointer to Accelerator (0x3000_0000)
    lui   s1, 0x30000
    # Base pointer to DMem Results (0x8000_2000)
    lui   s2, 0x80002

    # Inputs for accelerator: 12 * 10
    li    a0, 12
    li    a1, 10

    # 1. Sample START mtime (0x0200C000 - 8 = 0x0200BFF8)
    lw    t0, -8(s0)

    # 2. Trigger Accelerator Transaction
    sw    a0, 0x0(s1)         # Write Operand A
    sw    a1, 0x4(s1)         # Write Operand B
    lw    a2, 0x8(s1)         # Read Product

    # 3. Sample END mtime
    lw    t1, -8(s0)

    # 4. Compute Duration: elapsed = t1 - t0
    sub   t2, t1, t0

    # 5. Store Results to Data RAM
    sw    a2, 0x000(s2)       # 0x80002000 = Product (120 = 0x78)
    sw    t2, 0x004(s2)       # 0x80002004 = Elapsed Clock Cycles

done:
    wfi
    j     done
