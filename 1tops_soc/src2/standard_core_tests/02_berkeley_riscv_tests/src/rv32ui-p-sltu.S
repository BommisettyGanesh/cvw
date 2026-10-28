#include "riscv_test.h"
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
