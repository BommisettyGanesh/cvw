#!/usr/bin/env python3
"""
Generates UC Berkeley self-checking ISA tests (rv32ui) for RISC-V CPU Core testing.
Each test follows the standard riscv-tests structure and reports success via `tohost = 1`.
"""

import os

SRC_DIR = os.path.join(os.path.dirname(__file__), "src")
os.makedirs(SRC_DIR, exist_ok=True)

def write_test(filename, content):
    path = os.path.join(SRC_DIR, filename)
    with open(path, "w") as f:
        f.write(content)
    print(f"Generated {filename}")

# 1. ADD
write_test("rv32ui-p-add.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_RR_OP( 2,  add, 0x00000000, 0x00000000, 0x00000000 );
  TEST_RR_OP( 3,  add, 0x00000002, 0x00000001, 0x00000001 );
  TEST_RR_OP( 4,  add, 0x0000000a, 0x00000003, 0x00000007 );
  TEST_RR_OP( 5,  add, 0xffffffff, 0x00000000, 0xffffffff );
  TEST_RR_OP( 6,  add, 0xffffffff, 0xffffffff, 0x00000000 );
  TEST_RR_OP( 7,  add, 0xfffffffe, 0xffffffff, 0xffffffff );
  TEST_RR_OP( 8,  add, 0x00000000, 0x00000001, 0xffffffff );
  TEST_RR_OP( 9,  add, 0x80000000, 0x7fffffff, 0x00000001 );
  TEST_RR_OP( 10, add, 0x7fffffff, 0x80000000, 0xffffffff );

  TEST_RR_SRC1_EQ_DEST( 11, add, 24, 13, 11 );
  TEST_RR_SRC2_EQ_DEST( 12, add, 35, 14, 21 );
  TEST_RR_SRC12_EQ_DEST( 13, add, 64, 32 );
  TEST_RR_ZEROSRC1( 14, add, 15, 15 );
  TEST_RR_ZEROSRC2( 15, add, 18, 18 );
  TEST_RR_ZEROSRC12( 16, add, 0 );
  TEST_RR_ZERODEST( 17, add, 10, 20 );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
""")

# 2. ADDI
write_test("rv32ui-p-addi.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_IMM_OP( 2,  addi, 0x00000000, 0x00000000, 0x000 );
  TEST_IMM_OP( 3,  addi, 0x00000002, 0x00000001, 0x001 );
  TEST_IMM_OP( 4,  addi, 0x0000000a, 0x00000003, 0x007 );
  TEST_IMM_OP( 5,  addi, 0xffffffff, 0x00000000, -1 );
  TEST_IMM_OP( 6,  addi, 0x00000000, 0x00000001, -1 );
  TEST_IMM_OP( 7,  addi, 0x000007ff, 0x00000000, 0x7ff );
  TEST_IMM_OP( 8,  addi, 0xfffff800, 0x00000000, -2048 );

  TEST_IMM_SRC1_EQ_DEST( 9, addi, 40, 15, 25 );
  TEST_IMM_ZEROSRC1( 10, addi, 100, 100 );
  TEST_IMM_ZERODEST( 11, addi, 50, 50 );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
""")

# 3. SUB
write_test("rv32ui-p-sub.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_RR_OP( 2,  sub, 0x00000000, 0x00000000, 0x00000000 );
  TEST_RR_OP( 3,  sub, 0x00000000, 0x00000001, 0x00000001 );
  TEST_RR_OP( 4,  sub, 0xfffffffc, 0x00000003, 0x00000007 );
  TEST_RR_OP( 5,  sub, 0x00000001, 0x00000000, 0xffffffff );
  TEST_RR_OP( 6,  sub, 0x7fffffff, 0x80000000, 0x00000001 );
  TEST_RR_OP( 7,  sub, 0x80000000, 0x7fffffff, 0xffffffff );

  TEST_RR_SRC1_EQ_DEST( 8, sub, 15, 35, 20 );
  TEST_RR_SRC2_EQ_DEST( 9, sub, -5, 10, 15 );
  TEST_RR_SRC12_EQ_DEST( 10, sub, 0, 50 );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
""")

# 4. AND, OR, XOR
write_test("rv32ui-p-and.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_RR_OP( 2, and, 0x00000000, 0x00000000, 0x00000000 );
  TEST_RR_OP( 3, and, 0x00000000, 0x0000ffff, 0xffff0000 );
  TEST_RR_OP( 4, and, 0x000000aa, 0x000000ff, 0x000000aa );
  TEST_RR_OP( 5, and, 0x12345678, 0x12345678, 0xffffffff );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
""")

write_test("rv32ui-p-or.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_RR_OP( 2, or, 0x00000000, 0x00000000, 0x00000000 );
  TEST_RR_OP( 3, or, 0xffffffff, 0x0000ffff, 0xffff0000 );
  TEST_RR_OP( 4, or, 0x000000ff, 0x00000055, 0x000000aa );
  TEST_RR_OP( 5, or, 0x12345678, 0x12345678, 0x00000000 );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
""")

write_test("rv32ui-p-xor.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_RR_OP( 2, xor, 0x00000000, 0x00000000, 0x00000000 );
  TEST_RR_OP( 3, xor, 0xffffffff, 0x0000ffff, 0xffff0000 );
  TEST_RR_OP( 4, xor, 0x000000ff, 0x00000055, 0x000000aa );
  TEST_RR_OP( 5, xor, 0x00000000, 0x12345678, 0x12345678 );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
""")

# 5. SHIFTS: SLL, SRL, SRA
write_test("rv32ui-p-sll.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_RR_OP( 2, sll, 0x00000001, 0x00000001, 0 );
  TEST_RR_OP( 3, sll, 0x00000002, 0x00000001, 1 );
  TEST_RR_OP( 4, sll, 0x00000080, 0x00000001, 7 );
  TEST_RR_OP( 5, sll, 0x80000000, 0x00000001, 31 );
  TEST_RR_OP( 6, sll, 0x00000002, 0x00000001, 33 ); # shift amount masked to 5 bits

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
""")

write_test("rv32ui-p-srl.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_RR_OP( 2, srl, 0x80000000, 0x80000000, 0 );
  TEST_RR_OP( 3, srl, 0x40000000, 0x80000000, 1 );
  TEST_RR_OP( 4, srl, 0x01000000, 0x80000000, 7 );
  TEST_RR_OP( 5, srl, 0x00000001, 0x80000000, 31 );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
""")

write_test("rv32ui-p-sra.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_RR_OP( 2, sra, 0x80000000, 0x80000000, 0 );
  TEST_RR_OP( 3, sra, 0xc0000000, 0x80000000, 1 );
  TEST_RR_OP( 4, sra, 0xff000000, 0x80000000, 7 );
  TEST_RR_OP( 5, sra, 0xffffffff, 0x80000000, 31 );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
""")

# 6. SLT, SLTU
write_test("rv32ui-p-slt.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_RR_OP( 2, slt, 0, 0, 0 );
  TEST_RR_OP( 3, slt, 0, 1, 1 );
  TEST_RR_OP( 4, slt, 1, 0, 1 );
  TEST_RR_OP( 5, slt, 0, 1, 0 );
  TEST_RR_OP( 6, slt, 1, -1, 0 );
  TEST_RR_OP( 7, slt, 0, 0, -1 );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
""")

write_test("rv32ui-p-sltu.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_RR_OP( 2, sltu, 0, 0, 0 );
  TEST_RR_OP( 3, sltu, 0, 1, 1 );
  TEST_RR_OP( 4, sltu, 1, 0, 1 );
  TEST_RR_OP( 5, sltu, 0, 1, 0 );
  TEST_RR_OP( 6, sltu, 0, -1, 0 );
  TEST_RR_OP( 7, sltu, 1, 0, -1 );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
""")

# 7. LUI, AUIPC
write_test("rv32ui-p-lui.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_CASE( 2, x1, 0x00000000, lui x1, 0x0 );
  TEST_CASE( 3, x1, 0x00001000, lui x1, 0x1 );
  TEST_CASE( 4, x1, 0x00002000, lui x1, 0x2 );
  TEST_CASE( 5, x1, 0x80000000, lui x1, 0x80000 );
  TEST_CASE( 6, x1, 0xfffff000, lui x1, 0xfffff );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
""")

write_test("rv32ui-p-auipc.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

test_2:
  li  gp, 2
1:
  auipc x1, 0x0
  la    x2, 1b
  bne   x1, x2, fail

test_3:
  li  gp, 3
1:
  auipc x1, 0x1
  la    x2, 1b
  li    t1, 0x1000
  add   x2, x2, t1
  bne   x1, x2, fail

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
""")

# 8. BRANCHES: BEQ, BNE, BLT, BGE, BLTU, BGEU
write_test("rv32ui-p-beq.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_BR_OP( 2, beq, 0, 0, 1 );
  TEST_BR_OP( 3, beq, 1, 1, 1 );
  TEST_BR_OP( 4, beq, 0, 1, 0 );
  TEST_BR_OP( 5, beq, 1, 0, 0 );
  TEST_BR_OP( 6, beq, -1, 1, 0 );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
""")

write_test("rv32ui-p-bne.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_BR_OP( 2, bne, 0, 0, 0 );
  TEST_BR_OP( 3, bne, 1, 1, 0 );
  TEST_BR_OP( 4, bne, 0, 1, 1 );
  TEST_BR_OP( 5, bne, 1, 0, 1 );
  TEST_BR_OP( 6, bne, -1, 1, 1 );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
""")

write_test("rv32ui-p-blt.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_BR_OP( 2, blt, 0, 0, 0 );
  TEST_BR_OP( 3, blt, 0, 1, 1 );
  TEST_BR_OP( 4, blt, 1, 0, 0 );
  TEST_BR_OP( 5, blt, -1, 0, 1 );
  TEST_BR_OP( 6, blt, 0, -1, 0 );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
""")

write_test("rv32ui-p-bge.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_BR_OP( 2, bge, 0, 0, 1 );
  TEST_BR_OP( 3, bge, 1, 1, 1 );
  TEST_BR_OP( 4, bge, 0, 1, 0 );
  TEST_BR_OP( 5, bge, 1, 0, 1 );
  TEST_BR_OP( 6, bge, -1, 0, 0 );
  TEST_BR_OP( 7, bge, 0, -1, 1 );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
""")

# 9. JAL, JALR
write_test("rv32ui-p-jal.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

test_2:
  li  gp, 2
  li  x1, 0
1:
  jal x2, target_2
  li  x1, 1
target_2:
  la  t0, 1b
  addi t0, t0, 4
  bne x2, t0, fail
  bne x1, x0, fail

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
""")

write_test("rv32ui-p-jalr.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

test_2:
  li  gp, 2
  li  x1, 0
  la  t1, target_2
1:
  jalr x2, 0(t1)
  li  x1, 1
target_2:
  la  t0, 1b
  addi t0, t0, 4
  bne x2, t0, fail
  bne x1, x0, fail

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
""")

# 10. LOAD & STORE (LW, LH, LHU, LB, LBU, SW, SH, SB)
write_test("rv32ui-p-lw.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_LD_OP( 2, lw, 0x12345678, 0,  tdat );
  TEST_LD_OP( 3, lw, 0xffffffff, 4,  tdat );
  TEST_LD_OP( 4, lw, 0x00000000, 8,  tdat );
  TEST_LD_OP( 5, lw, 0xdeadbeef, 12, tdat );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
tdat:
  .word 0x12345678
  .word 0xffffffff
  .word 0x00000000
  .word 0xdeadbeef
RVTEST_DATA_END
""")

write_test("rv32ui-p-sw.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_ST_OP( 2, sw, lw, 0xaabbccdd, 0,  tdat );
  TEST_ST_OP( 3, sw, lw, 0x11223344, 4,  tdat );
  TEST_ST_OP( 4, sw, lw, 0x00000000, 8,  tdat );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
tdat:
  .word 0
  .word 0
  .word 0
RVTEST_DATA_END
""")

# 11. PIPELINE HAZARDS & FORWARDING STRESS
write_test("rv32ui-p-hazard.S", """#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  # Test RAW Hazard Ex-to-Ex Forwarding
test_2:
  li  gp, 2
  li  x1, 10
  addi x2, x1, 5   # x1 forwarded from EX stage
  li  t0, 15
  bne x2, t0, fail

  # Test RAW Hazard Mem-to-Ex Forwarding
test_3:
  li  gp, 3
  li  x1, 20
  nop
  addi x2, x1, 7   # x1 forwarded from MEM stage
  li  t0, 27
  bne x2, t0, fail

  # Test Load-Use Delay / Pipeline Interlock Stall
test_4:
  li  gp, 4
  la  x3, tdat
  lw  x1, 0(x3)
  addi x2, x1, 1   # Load-use dependency requires 1-cycle stall
  li  t0, 0x12345679
  bne x2, t0, fail

  # Test WAW Register Hazard
test_5:
  li  gp, 5
  li  x1, 100
  li  x1, 200      # Back-to-back writes to x1
  li  t0, 200
  bne x1, t0, fail

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
tdat:
  .word 0x12345678
RVTEST_DATA_END
""")

print("[+] All Berkeley ISA tests generated successfully.")
