/*
 * =============================================================================
 * Embench-IoT Benchmark Harness for Pure RISC-V CPU Core
 * =============================================================================
 */

#include "support.h"
#include <stdio.h>
#include <stdint.h>

extern uint32_t rdcycle(void);
extern uint32_t rdinstret(void);
extern void tohost_exit(int code);

static uint32_t start_cycles, end_cycles, user_cycles;
static uint32_t start_inst, end_inst, user_inst;

void initialise_board(void) {
    // Zero uncore board peripherals needed
}

void start_trigger(void) {
    start_inst   = rdinstret();
    start_cycles = rdcycle();
}

void stop_trigger(void) {
    end_cycles = rdcycle();
    end_inst   = rdinstret();
}

int main(void) {
    volatile int result;
    int correct;

    printf("\n==================================================\n");
    printf("     Embench-IoT Algorithmic Benchmark (RV32I)    \n");
    printf("==================================================\n");
    printf("Target Core  : Pure riscv_cpu Core (Core Only)\n");
    printf("Bus Protocol : AMBA 3 AHB-Lite Synchronous RAM\n");
    printf("Initializing kernel data structures...\n");

    initialise_board();
    initialise_benchmark();

    printf("Executing benchmark kernel...\n");
    start_trigger();
    result = benchmark();
    stop_trigger();

    user_cycles = end_cycles - start_cycles;
    user_inst   = end_inst - start_inst;

    printf("Verifying computational correctness...\n");
    correct = verify_benchmark(result);

    printf("\n--- Performance Metrics ---\n");
    printf("  Kernel Cycles  : %u\n", user_cycles);
    printf("  Retired Instrs : %u\n", user_inst);
    if (user_inst > 0 && user_cycles > 0) {
        uint32_t cpi_int  = user_cycles / user_inst;
        uint32_t cpi_frac = ((user_cycles % user_inst) * 100) / user_inst;
        printf("  Core CPI       : %u.%02u\n", cpi_int, cpi_frac);
        printf("  Core IPC       : 0.%02u\n", (user_inst * 100) / user_cycles);
    }
    printf("==================================================\n");

    if (correct) {
        printf(">>> [PASS] EMBENCH KERNEL VERIFICATION PASSED! <<<\n\n");
        tohost_exit(1);
    } else {
        printf(">>> [FAIL] EMBENCH KERNEL VERIFICATION FAILED (result=%d)! <<<\n\n", result);
        tohost_exit(0);
    }

    return 0;
}
