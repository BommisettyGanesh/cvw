#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_RR_OP( 2,  sub, 0x00000000, 0x00000000, 0x00000000 );
  TEST_RR_OP( 3,  sub, 0x00000000, 0x00000001, 0x00000001 );
  TEST_RR_OP( 4,  sub, 0xfffffffc, 0x00000003, 0x00000007 );
  TEST_RR_OP( 5,  sub, 0x00000001, 0x00000000, 0xffffffff );
  TEST_RR_OP( 6,  sub, 0x7fffffff, 0x80000000, 0x00000001 );
  TEST_RR_OP( 7,  sub, 0x80000000, 0x7fffffff, 0xffffffff );

  TEST_RR_SRC1_EQ_DEST( 8, sub, 15, 35, 20 );
  TEST_RR_SRC2_EQ_DEST( 9, sub, -5, 10, 15 );
  TEST_RR_SRC12_EQ_DEST( 10, sub, 0, 50 );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
