#!/usr/bin/env python3
"""
Google RISCV-DV / Constrained Random Instruction Torture Generator
Generates assembly tests stressing CPU pipeline hazards, interlocks, and branch speculation.
"""

import os
import random

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = SCRIPT_DIR

def generate_raw_hazards_test(filepath):
    """Test 1: Intense RAW Hazard Dependency Chains (EX-EX, MEM-EX, WB-EX forwarding)."""
    with open(filepath, "w") as f:
        f.write('''#include "torture.h"

TORTURE_INIT

    /* =========================================================================
     * SECTION 1: Distance-1 Back-to-Back RAW Hazards (EX-to-EX Forwarding)
     * ========================================================================= */
    li x5, 10
    li x6, 20
    add x7, x5, x6      /* x7 = 30 */
    addi x8, x7, 5      /* x8 = 35 (RAW on x7, distance 1) */
    sub x9, x8, x5      /* x9 = 25 (RAW on x8, distance 1) */
    slli x10, x9, 2     /* x10 = 100 (RAW on x9, distance 1) */
    xor x11, x10, x6    /* x11 = 100 ^ 20 = 112 (RAW on x10, distance 1) */
    CHECK_VAL(x11, 112, 1)

    /* =========================================================================
     * SECTION 2: Distance-2 RAW Hazards (MEM-to-EX Forwarding)
     * ========================================================================= */
    li x12, 50
    addi x13, x12, 15   /* x13 = 65 */
    nop
    sub x14, x13, x12   /* x14 = 15 (RAW on x13, distance 2) */
    nop
    srai x15, x14, 1    /* x15 = 7 (RAW on x14, distance 2) */
    CHECK_VAL(x15, 7, 2)

    /* =========================================================================
     * SECTION 3: Distance-3 RAW Hazards (WB-to-EX Register Bypass)
     * ========================================================================= */
    li x16, 200
    addi x17, x16, 55   /* x17 = 255 */
    nop
    nop
    andi x18, x17, 0x0f /* x18 = 15 (RAW on x17, distance 3) */
    CHECK_VAL(x18, 15, 3)

    /* =========================================================================
     * SECTION 4: Multi-Register Dual-Operand Forwarding Chains
     * rs1 forwarded from EX, rs2 forwarded from MEM
     * ========================================================================= */
    li x19, 100
    li x20, 200
    add x21, x19, x20   /* x21 = 300 */
    sub x22, x20, x19   /* x22 = 100 */
    add x23, x22, x21   /* x23 = 100 + 300 = 400 (rs1 from EX, rs2 from MEM) */
    CHECK_VAL(x23, 400, 4)

    /* =========================================================================
     * SECTION 5: 32-Instruction Forwarding Ring Torture
     * ========================================================================= */
    li x1, 1
''')
        # Generate 30 consecutive dependent adds
        accum = 1
        for i in range(2, 32):
            prev = i - 1
            curr = i
            accum += curr
            f.write(f"    addi x{curr}, x{prev}, {curr}\n")
        
        f.write(f"    CHECK_VAL(x31, {accum}, 5)\n\n")
        f.write("    TORTURE_PASS\n")
        f.write("TRAP_HANDLER\n")
        f.write("TOHOST_SECTION\n")

def generate_load_use_hazard_test(filepath):
    """Test 2: Load-Use Hazard Interlock Stalls (LW followed by dependent ALU)."""
    with open(filepath, "w") as f:
        f.write('''#include "torture.h"

TORTURE_INIT

    /* Setup scratchpad memory on stack */
    li t0, 0x12345678
    sw t0, 0(sp)
    li t1, 0x0000a5a5
    sw t1, 4(sp)
    li t2, 0xffffff80
    sw t2, 8(sp)

    /* =========================================================================
     * SECTION 1: Distance-1 Load-Use Hazard (LW -> ADD)
     * Core MUST insert hardware stall and forward data from MEM/WB stage
     * ========================================================================= */
    lw x5, 0(sp)
    addi x6, x5, 1      /* Load-Use hazard! */
    CHECK_VAL(x6, 0x12345679, 1)

    /* =========================================================================
     * SECTION 2: Load-Use Hazard with Subword Loads (LH, LHU, LB, LBU)
     * ========================================================================= */
    /* Halfword unsigned */
    lhu x7, 4(sp)
    slli x8, x7, 4      /* Load-Use on x7 */
    CHECK_VAL(x8, 0x0005a50, 2)

    /* Byte signed (testing sign-extension forwarding) */
    lb x9, 8(sp)
    addi x10, x9, 10    /* x9 = -128, x10 = -118 */
    CHECK_VAL(x10, -118, 3)

    /* Byte unsigned (testing zero-extension forwarding) */
    lbu x11, 8(sp)
    addi x12, x11, 10   /* x11 = 128, x12 = 138 */
    CHECK_VAL(x12, 138, 4)

    /* =========================================================================
     * SECTION 3: Store-to-Load with Immediate Load-Use Chain
     * ========================================================================= */
    li x13, 0xdeadbeef
    sw x13, 12(sp)
    lw x14, 12(sp)      /* RAW hazard via memory */
    xori x15, x14, 0x5a /* Load-Use on x14 */
    CHECK_VAL(x15, 0xdeadbeb5, 5)

    /* =========================================================================
     * SECTION 4: Dual Back-to-Back Load-Use Operations
     * ========================================================================= */
    lw x16, 0(sp)
    lw x17, 4(sp)
    add x18, x16, x17   /* rs1 from LW x17 (dist 1), rs2 from LW x16 (dist 2) */
    CHECK_VAL(x18, 0x1235001d, 6)

    TORTURE_PASS
TRAP_HANDLER
TOHOST_SECTION
''')

def generate_branch_storm_test(filepath):
    """Test 3: Branch Storm & Speculation Stress (rapid alternating branches & loops)."""
    with open(filepath, "w") as f:
        f.write('''#include "torture.h"

TORTURE_INIT

    /* =========================================================================
     * SECTION 1: Alternating Taken / Not-Taken Branches
     * ========================================================================= */
    li x5, 100
    li x6, 200

    /* Branch 1: BEQ Not Taken */
    beq x5, x6, 99f
    addi x7, x0, 1

    /* Branch 2: BNE Taken */
    bne x5, x6, 1f
    j 99f
1:  addi x7, x7, 1      /* x7 = 2 */

    /* Branch 3: BLT Taken */
    blt x5, x6, 2f
    j 99f
2:  addi x7, x7, 1      /* x7 = 3 */

    /* Branch 4: BGE Not Taken */
    bge x5, x6, 99f
    addi x7, x7, 1      /* x7 = 4 */

    /* Branch 5: BLTU Taken */
    bltu x5, x6, 3f
    j 99f
3:  addi x7, x7, 1      /* x7 = 5 */

    /* Branch 6: BGEU Not Taken */
    bgeu x5, x6, 99f
    addi x7, x7, 1      /* x7 = 6 */

    CHECK_VAL(x7, 6, 1)

    /* =========================================================================
     * SECTION 2: Nested Loop Execution (1,000 branch instructions total)
     * Outer: 50, Inner: 20
     * ========================================================================= */
    li x8, 0            /* Outer loop counter */
    li x9, 0            /* Total iterations accumulator */
outer_loop:
    li x10, 0           /* Inner loop counter */
inner_loop:
    addi x9, x9, 1
    addi x10, x10, 1
    li t1, 20
    blt x10, t1, inner_loop

    addi x8, x8, 1
    li t2, 50
    blt x8, t2, outer_loop

    CHECK_VAL(x9, 1000, 2)

    /* =========================================================================
     * SECTION 3: Rapid Jumps (JAL / JALR Pipeline Redirection)
     * ========================================================================= */
    jal x1, jump_target1
    j 99f
jump_target1:
    addi x1, x1, 12     /* Target return address */
    jalr x0, x1, 0
    j 99f
    nop
    addi x11, x0, 77
    CHECK_VAL(x11, 77, 3)

    TORTURE_PASS

99: TORTURE_FAIL(0xbad)
TRAP_HANDLER
TOHOST_SECTION
''')

def generate_memory_stress_test(filepath):
    """Test 4: Mixed Subword Loads and Stores (SB, SH, SW, LB, LH, LW alignment stress)."""
    with open(filepath, "w") as f:
        f.write('''#include "torture.h"

TORTURE_INIT

    /* =========================================================================
     * SECTION 1: Interleaved Byte Writes to Reconstruct Full Word
     * Store 4 individual bytes (0x78, 0x56, 0x34, 0x12) into same 32-bit word
     * ========================================================================= */
    li t0, 0x78
    sb t0, 0(sp)
    li t0, 0x56
    sb t0, 1(sp)
    li t0, 0x34
    sb t0, 2(sp)
    li t0, 0x12
    sb t0, 3(sp)

    lw x5, 0(sp)
    CHECK_VAL(x5, 0x12345678, 1)

    /* =========================================================================
     * SECTION 2: Interleaved Halfword Writes
     * ========================================================================= */
    li t0, 0xcafe
    sh t0, 4(sp)
    li t0, 0xbabe
    sh t0, 6(sp)

    lw x6, 4(sp)
    CHECK_VAL(x6, 0xbabecafe, 2)

    /* =========================================================================
     * SECTION 3: Subword Reads from Pre-loaded Word (Sign vs Zero Extension)
     * ========================================================================= */
    li t0, 0x81828384
    sw t0, 8(sp)

    /* Signed byte reads */
    lb x7, 8(sp)        /* 0x84 -> 0xffffff84 (-124) */
    CHECK_VAL(x7, -124, 3)
    lb x8, 9(sp)        /* 0x83 -> 0xffffff83 (-125) */
    CHECK_VAL(x8, -125, 4)

    /* Unsigned byte reads */
    lbu x9, 8(sp)       /* 0x84 -> 0x00000084 (132) */
    CHECK_VAL(x9, 132, 5)

    /* Signed halfword reads */
    lh x10, 8(sp)       /* 0x8384 -> 0xffff8384 (-31868) */
    CHECK_VAL(x10, -31868, 6)

    /* Unsigned halfword reads */
    lhu x11, 10(sp)     /* 0x8182 -> 0x00008182 (33154) */
    CHECK_VAL(x11, 33154, 7)

    TORTURE_PASS
TRAP_HANDLER
TOHOST_SECTION
''')

def generate_complex_random_test(filepath, seed=12345, num_instructions=150):
    """Test 5: Constrained Random Instruction Sequence with Rolling Signature Accumulator."""
    random.seed(seed)
    
    with open(filepath, "w") as f:
        f.write('''#include "torture.h"

TORTURE_INIT

    /* x20 is the Rolling Signature Checksum Register */
    li x20, 0x12345678
    
    /* Initialize working registers */
    li x5, 1
    li x6, 2
    li x7, 3
    li x8, 4
    li x9, 5
    li x10, 6
    li x11, 7
    li x12, 8
    li x13, 9
    li x14, 10
    li x15, 11
''')

        regs = [f"x{i}" for i in range(5, 16)]
        
        # Simulate in Python to get golden signature
        reg_vals = {r: int(r[1:]) - 4 for r in regs}
        sig = 0x12345678
        mask32 = 0xffffffff

        for step in range(num_instructions):
            op = random.choice(["add", "sub", "xor", "or", "and", "sll", "srl", "sra"])
            rd = random.choice(regs)
            rs1 = random.choice(regs)
            rs2 = random.choice(regs)
            
            v1 = reg_vals[rs1]
            v2 = reg_vals[rs2]
            
            if op == "add":
                res = (v1 + v2) & mask32
            elif op == "sub":
                res = (v1 - v2) & mask32
            elif op == "xor":
                res = (v1 ^ v2) & mask32
            elif op == "or":
                res = (v1 | v2) & mask32
            elif op == "and":
                res = (v1 & v2) & mask32
            elif op == "sll":
                res = (v1 << (v2 & 0x1f)) & mask32
            elif op == "srl":
                res = ((v1 & mask32) >> (v2 & 0x1f)) & mask32
            elif op == "sra":
                s1 = v1 if v1 < 0x80000000 else v1 - 0x100000000
                res = (s1 >> (v2 & 0x1f)) & mask32

            reg_vals[rd] = res
            
            # Signature accumulation: sig = (sig ^ res) + (sig << 1) + 0x3b
            sig = ((sig ^ res) + ((sig << 1) & mask32) + 0x3b) & mask32

            f.write(f"    {op} {rd}, {rs1}, {rs2}\n")
            f.write(f"    xor x20, x20, {rd}\n")
            f.write(f"    slli t0, x20, 1\n")
            f.write(f"    add x20, x20, t0\n")
            f.write(f"    addi x20, x20, 0x3b\n")

        f.write(f"\n    /* Golden signature check */\n")
        f.write(f"    CHECK_VAL(x20, {hex(sig)}, 1)\n\n")
        f.write("    TORTURE_PASS\n")
        f.write("TRAP_HANDLER\n")
        f.write("TOHOST_SECTION\n")

def main():
    os.makedirs(SRC_DIR, exist_ok=True)
    generate_raw_hazards_test(os.path.join(SRC_DIR, "torture_raw_hazards.S"))
    generate_load_use_hazard_test(os.path.join(SRC_DIR, "torture_load_use_hazard.S"))
    generate_branch_storm_test(os.path.join(SRC_DIR, "torture_branch_storm.S"))
    generate_memory_stress_test(os.path.join(SRC_DIR, "torture_memory_stress.S"))
    generate_complex_random_test(os.path.join(SRC_DIR, "torture_complex_random.S"))
    print("[+] All 5 Google RISCV-DV / Torture assembly tests successfully generated.")

if __name__ == "__main__":
    main()
