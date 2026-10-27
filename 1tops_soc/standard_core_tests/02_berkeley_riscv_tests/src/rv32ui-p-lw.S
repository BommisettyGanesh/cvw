#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  TEST_LD_OP( 2, lw, 0x12345678, 0,  tdat );
  TEST_LD_OP( 3, lw, 0xffffffff, 4,  tdat );
  TEST_LD_OP( 4, lw, 0x00000000, 8,  tdat );
  TEST_LD_OP( 5, lw, 0xdeadbeef, 12, tdat );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
tdat:
  .word 0x12345678
  .word 0xffffffff
  .word 0x00000000
  .word 0xdeadbeef
RVTEST_DATA_END
