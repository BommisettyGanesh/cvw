#include "coremark.h"
#include "core_portme.h"
#include "uart.h"
#include <stdio.h>

#if (MEM_METHOD == MEM_MALLOC)
void *portable_malloc(size_t size) { return NULL; }
void portable_free(void *p) { (void)p; }
#endif

#if (SEED_METHOD == SEED_VOLATILE)
#ifndef ITERATIONS
#define ITERATIONS 1
#endif
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;
#endif

ee_u32 default_num_contexts = 1;

static CORE_TICKS start_time_val, stop_time_val;
static uint32_t start_inst_val, stop_inst_val;

void start_time(void) {
    start_inst_val = rdinstret();
    start_time_val = rdcycle();
}

void stop_time(void) {
    stop_time_val = rdcycle();
    stop_inst_val = rdinstret();
}

CORE_TICKS get_time(void) {
    return rdcycle();
}

secs_ret time_in_secs(CORE_TICKS ticks) {
    // ticks is clock cycles at 100MHz (100,000,000 cycles per sec)
    // Avoid floating point: return scaled or integer seconds
    return (secs_ret)(ticks / EE_TICKS_PER_SEC);
}

void portable_init(core_portable *p, int *argc, char *argv[]) {
    (void)argc;
    (void)argv;
    uart_init();
    p->portable_id = 0;
    ee_printf("\n==================================================\n");
    ee_printf("     EEMBC CoreMark 1.0 Benchmark (RV32I)         \n");
    ee_printf("==================================================\n");
    ee_printf("Target Core  : RISC-V 5-Stage Pipelined SoC\n");
    ee_printf("Bus Standard : AMBA 3 AHB-Lite\n");
    ee_printf("ISA Extensions: RV32I + Zicsr + Zicntr + Zifencei\n");
    ee_printf("Iterations   : %d\n", (int)seed4_volatile);
    ee_printf("Starting benchmark execution...\n\n");
}

void portable_fini(core_portable *p) {
    (void)p;
    uint32_t total_cycles = stop_time_val - start_time_val;
    uint32_t total_insts  = stop_inst_val - start_inst_val;

    ee_printf("\n--- CoreMark Hardware Performance Summary ---\n");
    ee_printf("  Total Benchmark Cycles : %u\n", total_cycles);
    ee_printf("  Total Instructions Done: %u\n", total_insts);
    if (total_insts > 0) {
        uint32_t cpi_int  = total_cycles / total_insts;
        uint32_t cpi_frac = ((total_cycles % total_insts) * 100) / total_insts;
        ee_printf("  Core CPI               : %u.%02u\n", cpi_int, cpi_frac);
        ee_printf("  Core IPC               : 0.%02u\n", (total_insts * 100) / total_cycles);
    }
    ee_printf("==================================================\n");
}
