#include "riscv_test.h"
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
