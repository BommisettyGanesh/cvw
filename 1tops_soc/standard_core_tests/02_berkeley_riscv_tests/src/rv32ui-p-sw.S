#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_ST_OP( 2, sw, lw, 0xaabbccdd, 0,  tdat );
  TEST_ST_OP( 3, sw, lw, 0x11223344, 4,  tdat );
  TEST_ST_OP( 4, sw, lw, 0x00000000, 8,  tdat );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
tdat:
  .word 0
  .word 0
  .word 0
RVTEST_DATA_END
