#include "riscv_test.h"
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
