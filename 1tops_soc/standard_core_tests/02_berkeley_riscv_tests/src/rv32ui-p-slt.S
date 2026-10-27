#include "riscv_test.h"
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
