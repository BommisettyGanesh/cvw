#include "riscv_test.h"
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
