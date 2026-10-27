#include "torture.h"

TORTURE_INIT

    /* =========================================================================
     * SECTION 1: Interleaved Byte Writes to Reconstruct Full Word
     * Store 4 individual bytes (0x78, 0x56, 0x34, 0x12) into same 32-bit word
     * ========================================================================= */
    li t0, 0x78
    sb t0, 0(sp)
    li t0, 0x56
    sb t0, 1(sp)
    li t0, 0x34
    sb t0, 2(sp)
    li t0, 0x12
    sb t0, 3(sp)

    lw x5, 0(sp)
    CHECK_VAL(x5, 0x12345678, 1)

    /* =========================================================================
     * SECTION 2: Interleaved Halfword Writes
     * ========================================================================= */
    li t0, 0xcafe
    sh t0, 4(sp)
    li t0, 0xbabe
    sh t0, 6(sp)

    lw x6, 4(sp)
    CHECK_VAL(x6, 0xbabecafe, 2)

    /* =========================================================================
     * SECTION 3: Subword Reads from Pre-loaded Word (Sign vs Zero Extension)
     * ========================================================================= */
    li t0, 0x81828384
    sw t0, 8(sp)

    /* Signed byte reads */
    lb x7, 8(sp)        /* 0x84 -> 0xffffff84 (-124) */
    CHECK_VAL(x7, -124, 3)
    lb x8, 9(sp)        /* 0x83 -> 0xffffff83 (-125) */
    CHECK_VAL(x8, -125, 4)

    /* Unsigned byte reads */
    lbu x9, 8(sp)       /* 0x84 -> 0x00000084 (132) */
    CHECK_VAL(x9, 132, 5)

    /* Signed halfword reads */
    lh x10, 8(sp)       /* 0x8384 -> 0xffff8384 (-31868) */
    CHECK_VAL(x10, -31868, 6)

    /* Unsigned halfword reads */
    lhu x11, 10(sp)     /* 0x8182 -> 0x00008182 (33154) */
    CHECK_VAL(x11, 33154, 7)

    TORTURE_PASS
TRAP_HANDLER
TOHOST_SECTION
