#include "riscv_test.h"
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
