#include "torture.h"

TORTURE_INIT

    /* =========================================================================
     * SECTION 1: Alternating Taken / Not-Taken Branches
     * ========================================================================= */
    li x5, 100
    li x6, 200

    /* Branch 1: BEQ Not Taken */
    beq x5, x6, 99f
    addi x7, x0, 1

    /* Branch 2: BNE Taken */
    bne x5, x6, 1f
    j 99f
1:  addi x7, x7, 1      /* x7 = 2 */

    /* Branch 3: BLT Taken */
    blt x5, x6, 2f
    j 99f
2:  addi x7, x7, 1      /* x7 = 3 */

    /* Branch 4: BGE Not Taken */
    bge x5, x6, 99f
    addi x7, x7, 1      /* x7 = 4 */

    /* Branch 5: BLTU Taken */
    bltu x5, x6, 3f
    j 99f
3:  addi x7, x7, 1      /* x7 = 5 */

    /* Branch 6: BGEU Not Taken */
    bgeu x5, x6, 99f
    addi x7, x7, 1      /* x7 = 6 */

    CHECK_VAL(x7, 6, 1)

    /* =========================================================================
     * SECTION 2: Nested Loop Execution (1,000 branch instructions total)
     * Outer: 50, Inner: 20
     * ========================================================================= */
    li x8, 0            /* Outer loop counter */
    li x9, 0            /* Total iterations accumulator */
outer_loop:
    li x10, 0           /* Inner loop counter */
inner_loop:
    addi x9, x9, 1
    addi x10, x10, 1
    li t1, 20
    blt x10, t1, inner_loop

    addi x8, x8, 1
    li t2, 50
    blt x8, t2, outer_loop

    CHECK_VAL(x9, 1000, 2)

    /* =========================================================================
     * SECTION 3: Rapid Jumps (JAL / JALR Pipeline Redirection)
     * ========================================================================= */
    jal x1, jump_target1
    j 99f
jump_target1:
    addi x1, x1, 12     /* Target return address */
    jalr x0, x1, 0
    j 99f
    nop
    addi x11, x0, 77
    CHECK_VAL(x11, 77, 3)

    TORTURE_PASS

99: TORTURE_FAIL(0xbad)
TRAP_HANDLER
TOHOST_SECTION
