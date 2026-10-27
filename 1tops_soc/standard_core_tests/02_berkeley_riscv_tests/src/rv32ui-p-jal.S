#include "riscv_test.h"
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
