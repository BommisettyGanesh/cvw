#include "riscv_test.h"
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
