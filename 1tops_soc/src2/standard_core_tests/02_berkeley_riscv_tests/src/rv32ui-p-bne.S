#include "riscv_test.h"
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
