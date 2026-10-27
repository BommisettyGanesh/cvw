#include "uart.h"
#include <stdio.h>

#define N 8

static int A[N][N];
static int B[N][N];
static int C[N][N];

void init_matrices(void) {
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            A[i][j] = (i + 1) * (j + 1);
            B[i][j] = (i == j) ? 2 : 1;
            C[i][j] = 0;
        }
    }
}

void matmul(void) {
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            int sum = 0;
            for (int k = 0; k < N; k++) {
                sum += A[i][k] * B[k][j];
            }
            C[i][j] = sum;
        }
    }
}

int main(void) {
    uart_init();
    printf("\n========================================\n");
    printf("   RISC-V Benchmark: Matrix Multiply    \n");
    printf("   Size: %dx%d Integer Matrix           \n", N, N);
    printf("========================================\n\n");

    printf("Initializing matrices...\n");
    init_matrices();

    printf("Starting timed matrix multiplication...\n");
    uint32_t c_start = rdcycle();
    uint32_t i_start = rdinstret();

    matmul();

    uint32_t c_end = rdcycle();
    uint32_t i_end = rdinstret();

    uint32_t delta_cycles = c_end - c_start;
    uint32_t delta_insts  = i_end - i_start;

    printf("Computation finished!\n\n");
    printf("--- Benchmark Metrics ---\n");
    printf("  Execution Cycles   : %u\n", delta_cycles);
    printf("  Instructions Done  : %u\n", delta_insts);
    if (delta_insts > 0) {
        uint32_t cpi_int = delta_cycles / delta_insts;
        uint32_t cpi_frac = ((delta_cycles % delta_insts) * 100) / delta_insts;
        printf("  Average CPI        : %u.%02u\n", cpi_int, cpi_frac);
    }

    // Verify C[0][0]:
    // A[0][k] = 1 * (k+1)
    // B[k][0] = 2 if k=0 else 1
    // sum = 1*2 + 2*1 + 3*1 + 4*1 + 5*1 + 6*1 + 7*1 + 8*1 = 2 + 35 = 37
    printf("\nValidation Check: C[0][0] = %d (Expected: 37)\n", C[0][0]);
    if (C[0][0] == 37) {
        printf("[SUCCESS] Matrix Multiplication Verified Correctly!\n");
        return 0;
    } else {
        printf("[FAILURE] Verification mismatch!\n");
        return 1;
    }
}
