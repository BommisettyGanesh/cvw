////////////////////////////////////////////////////////////////////////////////
// step_test.S
// Deterministic Single-Step Verification Program for CORE-V Wally RV32I Core
//
// Memory Layout:
//   IRAM : 0x80000000
//   DRAM : 0x80002000
//
// Execution Pattern:
//   Each instruction step advances execution and writes deterministic markers
//   to DRAM so that host debugger can verify individual retired instructions.
////////////////////////////////////////////////////////////////////////////////

.section .text
.globl _start

_start:
    # 1. Base pointer to Data RAM (0x80002000)
    lui   s0, 0x80002

    # 2. Step 1: Write marker 0x11111111 to 0x80002000
    li    t0, 0x11111111
    sw    t0, 0(s0)

    # 3. Step 2: Write marker 0x22222222 to 0x80002004
    li    t1, 0x22222222
    sw    t1, 4(s0)

    # 4. Step 3: Write marker 0x33333333 to 0x80002008
    li    t2, 0x33333333
    sw    t2, 8(s0)

    # 5. Step 4: Write sum (t0 + t1 = 0x33333333) to 0x8000200C
    add   t3, t0, t1
    sw    t3, 12(s0)

    # 6. Step 5: Write marker 0xCAFEBABE to 0x80002010
    li    t4, 0xCAFEBABE
    sw    t4, 16(s0)

loop:
    j     loop
