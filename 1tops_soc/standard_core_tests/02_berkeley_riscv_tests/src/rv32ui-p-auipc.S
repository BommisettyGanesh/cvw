#include "riscv_test.h"
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
