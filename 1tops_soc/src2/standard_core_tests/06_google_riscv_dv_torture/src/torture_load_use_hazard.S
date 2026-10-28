#include "torture.h"

TORTURE_INIT

    /* Setup scratchpad memory on stack */
    li t0, 0x12345678
    sw t0, 0(sp)
    li t1, 0x0000a5a5
    sw t1, 4(sp)
    li t2, 0xffffff80
    sw t2, 8(sp)

    /* =========================================================================
     * SECTION 1: Distance-1 Load-Use Hazard (LW -> ADD)
     * Core MUST insert hardware stall and forward data from MEM/WB stage
     * ========================================================================= */
    lw x5, 0(sp)
    addi x6, x5, 1      /* Load-Use hazard! */
    CHECK_VAL(x6, 0x12345679, 1)

    /* =========================================================================
     * SECTION 2: Load-Use Hazard with Subword Loads (LH, LHU, LB, LBU)
     * ========================================================================= */
    /* Halfword unsigned */
    lhu x7, 4(sp)
    slli x8, x7, 4      /* Load-Use on x7 */
    CHECK_VAL(x8, 0x0005a50, 2)

    /* Byte signed (testing sign-extension forwarding) */
    lb x9, 8(sp)
    addi x10, x9, 10    /* x9 = -128, x10 = -118 */
    CHECK_VAL(x10, -118, 3)

    /* Byte unsigned (testing zero-extension forwarding) */
    lbu x11, 8(sp)
    addi x12, x11, 10   /* x11 = 128, x12 = 138 */
    CHECK_VAL(x12, 138, 4)

    /* =========================================================================
     * SECTION 3: Store-to-Load with Immediate Load-Use Chain
     * ========================================================================= */
    li x13, 0xdeadbeef
    sw x13, 12(sp)
    lw x14, 12(sp)      /* RAW hazard via memory */
    xori x15, x14, 0x5a /* Load-Use on x14 */
    CHECK_VAL(x15, 0xdeadbeb5, 5)

    /* =========================================================================
     * SECTION 4: Dual Back-to-Back Load-Use Operations
     * ========================================================================= */
    lw x16, 0(sp)
    lw x17, 4(sp)
    add x18, x16, x17   /* rs1 from LW x17 (dist 1), rs2 from LW x16 (dist 2) */
    CHECK_VAL(x18, 0x1235001d, 6)

    TORTURE_PASS
TRAP_HANDLER
TOHOST_SECTION
