#include "uart.h"
#include <stdio.h>

#define NUM_ITEMS 64

static int arr[NUM_ITEMS];

static unsigned int lfsr = 0xACE1u;
static int pseudo_rand(void) {
    unsigned int lsb = lfsr & 1u;
    lfsr >>= 1;
    if (lsb) {
        lfsr ^= 0xB400u;
    }
    return (int)(lfsr % 1000);
}

void swap(int *a, int *b) {
    int temp = *a;
    *a = *b;
    *b = temp;
}

int partition(int *a, int low, int high) {
    int pivot = a[high];
    int i = low - 1;
    for (int j = low; j < high; j++) {
        if (a[j] <= pivot) {
            i++;
            swap(&a[i], &a[j]);
        }
    }
    swap(&a[i + 1], &a[high]);
    return i + 1;
}

void quicksort(int *a, int low, int high) {
    if (low < high) {
        int pi = partition(a, low, high);
        quicksort(a, low, pi - 1);
        quicksort(a, pi + 1, high);
    }
}

int main(void) {
    uart_init();
    printf("\n========================================\n");
    printf("   RISC-V Benchmark: QuickSort (64 int) \n");
    printf("========================================\n\n");

    printf("Generating unsorted pseudo-random array:\n");
    for (int i = 0; i < NUM_ITEMS; i++) {
        arr[i] = pseudo_rand();
    }

    printf("Unsorted first 8 elements: ");
    for (int i = 0; i < 8; i++) {
        printf("%d ", arr[i]);
    }
    printf("...\n");

    printf("\nStarting timed QuickSort...\n");
    uint32_t c_start = rdcycle();
    uint32_t i_start = rdinstret();

    quicksort(arr, 0, NUM_ITEMS - 1);

    uint32_t c_end = rdcycle();
    uint32_t i_end = rdinstret();

    uint32_t delta_cycles = c_end - c_start;
    uint32_t delta_insts  = i_end - i_start;

    printf("Sorting completed!\n\n");
    printf("Sorted first 8 elements: ");
    for (int i = 0; i < 8; i++) {
        printf("%d ", arr[i]);
    }
    printf("...\n\n");

    printf("--- Performance Metrics ---\n");
    printf("  Execution Cycles   : %u\n", delta_cycles);
    printf("  Instructions Done  : %u\n", delta_insts);
    if (delta_insts > 0) {
        printf("  Average CPI        : %u.%02u\n", delta_cycles / delta_insts, ((delta_cycles % delta_insts) * 100) / delta_insts);
    }

    // Verify sorted property
    int sorted_ok = 1;
    for (int i = 0; i < NUM_ITEMS - 1; i++) {
        if (arr[i] > arr[i + 1]) {
            sorted_ok = 0;
            printf("[ERROR] Inversion at index %d: %d > %d\n", i, arr[i], arr[i + 1]);
            break;
        }
    }

    if (sorted_ok) {
        printf("\n[SUCCESS] Array is verified to be monotonically sorted!\n");
        return 0;
    } else {
        printf("\n[FAILURE] Sort validation failed!\n");
        return 1;
    }
}
