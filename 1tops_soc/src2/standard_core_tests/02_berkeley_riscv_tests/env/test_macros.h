#ifndef _TEST_MACROS_H
#define _TEST_MACROS_H

#define TEST_CASE( testnum, testreg, correctval, code... ) \
test_ ## testnum: \
  li  gp, testnum; \
  code; \
  li  t0, correctval; \
  bne testreg, t0, fail;

#define TEST_RR_OP( testnum, inst, result, val1, val2 ) \
  TEST_CASE( testnum, x3, result, \
    li  x1, val1; \
    li  x2, val2; \
    inst x3, x1, x2; \
  )

#define TEST_RR_SRC1_EQ_DEST( testnum, inst, result, val1, val2 ) \
  TEST_CASE( testnum, x1, result, \
    li  x1, val1; \
    li  x2, val2; \
    inst x1, x1, x2; \
  )

#define TEST_RR_SRC2_EQ_DEST( testnum, inst, result, val1, val2 ) \
  TEST_CASE( testnum, x2, result, \
    li  x1, val1; \
    li  x2, val2; \
    inst x2, x1, x2; \
  )

#define TEST_RR_SRC12_EQ_DEST( testnum, inst, result, val1 ) \
  TEST_CASE( testnum, x1, result, \
    li  x1, val1; \
    inst x1, x1, x1; \
  )

#define TEST_RR_ZEROSRC1( testnum, inst, result, val ) \
  TEST_CASE( testnum, x2, result, \
    li  x1, val; \
    inst x2, x0, x1; \
  )

#define TEST_RR_ZEROSRC2( testnum, inst, result, val ) \
  TEST_CASE( testnum, x2, result, \
    li  x1, val; \
    inst x2, x1, x0; \
  )

#define TEST_RR_ZEROSRC12( testnum, inst, result ) \
  TEST_CASE( testnum, x1, result, \
    inst x1, x0, x0; \
  )

#define TEST_RR_ZERODEST( testnum, inst, val1, val2 ) \
  TEST_CASE( testnum, x0, 0, \
    li  x1, val1; \
    li  x2, val2; \
    inst x0, x1, x2; \
  )

#define TEST_IMM_OP( testnum, inst, result, val1, imm ) \
  TEST_CASE( testnum, x3, result, \
    li  x1, val1; \
    inst x3, x1, imm; \
  )

#define TEST_IMM_SRC1_EQ_DEST( testnum, inst, result, val1, imm ) \
  TEST_CASE( testnum, x1, result, \
    li  x1, val1; \
    inst x1, x1, imm; \
  )

#define TEST_IMM_ZEROSRC1( testnum, inst, result, imm ) \
  TEST_CASE( testnum, x1, result, \
    inst x1, x0, imm; \
  )

#define TEST_IMM_ZERODEST( testnum, inst, val1, imm ) \
  TEST_CASE( testnum, x0, 0, \
    li  x1, val1; \
    inst x0, x1, imm; \
  )

#define TEST_BR_OP( testnum, inst, val1, val2, taken ) \
test_ ## testnum: \
  li  gp, testnum; \
  li  x1, val1; \
  li  x2, val2; \
  li  x3, 0; \
  inst x1, x2, 1f; \
  j 2f; \
1: \
  li  x3, 1; \
2: \
  li  t0, taken; \
  bne x3, t0, fail;

#define TEST_LD_OP( testnum, inst, result, offset, base ) \
test_ ## testnum: \
  li  gp, testnum; \
  la  x1, base; \
  inst x3, offset(x1); \
  li  t0, result; \
  bne x3, t0, fail;

#define TEST_ST_OP( testnum, st_inst, ld_inst, result, offset, base ) \
test_ ## testnum: \
  li  gp, testnum; \
  la  x1, base; \
  li  x2, result; \
  st_inst x2, offset(x1); \
  ld_inst x3, offset(x1); \
  li  t0, result; \
  bne x3, t0, fail;

#define TEST_DATA

#define TEST_PASSFAIL \
  j pass; \
fail: \
  RVTEST_FAIL \
pass: \
  RVTEST_PASS

#endif
