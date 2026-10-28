#include "uart.h"
#include <stdio.h>

int main(void) {
    uart_init();
    printf("\n========================================\n");
    printf("   RISC-V 5-Stage Pipelined SoC (AHB)   \n");
    printf("   Bare-Metal C Environment Active!     \n");
    printf("========================================\n\n");

    printf("Executing simple loop and calculation:\n");
    int sum = 0;
    for (int i = 1; i <= 10; i++) {
        sum += i;
        printf("  Step %2d: sum = %d\n", i, sum);
    }
    printf("\nFinal Result: sum(1..10) = %d (Expected: 55)\n", sum);

    uint32_t cycles = rdcycle();
    uint32_t insts = rdinstret();
    printf("Hardware Performance Counters:\n");
    printf("  Cycles       : %u\n", cycles);
    printf("  Instructions : %u\n", insts);
    printf("  CPI          : %d.%02d\n\n", cycles / insts, ((cycles % insts) * 100) / insts);

    if (sum == 55) {
        printf("[SUCCESS] Hello World Test PASSED!\n");
        return 0;
    } else {
        printf("[FAILURE] Calculation mismatch!\n");
        return 1;
    }
}
