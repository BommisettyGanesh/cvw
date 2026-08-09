// tests/custom/my_baremetal_test/accel_test.c
// Bare-Metal C Test Application for Hardware Multiplier Accelerator

#define UART_BASE         0x10000000
#define GPIO_BASE         0x10002000
#define ACCEL_BASE        0x10004000

#define ACCEL_SRC_A       (*(volatile unsigned int *)(ACCEL_BASE + 0x00))
#define ACCEL_SRC_B       (*(volatile unsigned int *)(ACCEL_BASE + 0x04))
#define ACCEL_CTRL        (*(volatile unsigned int *)(ACCEL_BASE + 0x08))
#define ACCEL_STATUS      (*(volatile unsigned int *)(ACCEL_BASE + 0x0C))
#define ACCEL_RESULT_LO   (*(volatile unsigned int *)(ACCEL_BASE + 0x10))
#define ACCEL_RESULT_HI   (*(volatile unsigned int *)(ACCEL_BASE + 0x14))

void uart_putc(char c) {
    volatile char *uart = (char *)UART_BASE;
    *uart = c;
}

void uart_puts(const char *str) {
    while (*str) {
        uart_putc(*str++);
    }
}

unsigned int run_hardware_multiplier(unsigned int a, unsigned int b, unsigned int *result_hi) {
    // 1. Write operands A and B to hardware accelerator
    ACCEL_SRC_A = a;
    ACCEL_SRC_B = b;

    // 2. Pulse Start bit (Bit 0)
    ACCEL_CTRL = 0x1;

    // 3. Poll Status register until Done bit (Bit 0) is set
    while ((ACCEL_STATUS & 0x1) == 0);

    // 4. Return lower 32 bits and upper 32 bits
    *result_hi = ACCEL_RESULT_HI;
    return ACCEL_RESULT_LO;
}

void main() {
    volatile unsigned int *gpio = (unsigned int *)GPIO_BASE;
    unsigned int res_hi = 0;

    uart_puts("Starting Hardware Accelerator Test...\n");

    // --- Test 1: 1234 * 5678 = 7006652 ---
    unsigned int a1 = 1234;
    unsigned int b1 = 5678;
    unsigned int expected1_lo = 7006652;
    unsigned int expected1_hi = 0;

    unsigned int hw_res1_lo = run_hardware_multiplier(a1, b1, &res_hi);

    if (hw_res1_lo != expected1_lo || res_hi != expected1_hi) {
        uart_puts("FAIL: Test 1 Mismatch!\n");
        *gpio = 0xDEAD0001;
        while (1);
    }

    // --- Test 2: 0x12345678 * 0x00000002 = 0x2468ACF0 ---
    unsigned int a2 = 0x12345678;
    unsigned int b2 = 2;
    unsigned int expected2_lo = 0x2468ACF0;
    unsigned int expected2_hi = 0x0;

    unsigned int hw_res2_lo = run_hardware_multiplier(a2, b2, &res_hi);

    if (hw_res2_lo != expected2_lo || res_hi != expected2_hi) {
        uart_puts("FAIL: Test 2 Mismatch!\n");
        *gpio = 0xDEAD0002;
        while (1);
    }

    // --- All Tests Passed ---
    uart_puts("SUCCESS: Hardware Multiplier Accelerator Passed All Tests!\n");
    *gpio = 0x1; // Assert GPIO success signal

    while (1);
}
