#include <stdint.h>

// UART 16550 Base Address
#define UART_BASE 0x10000000
#define UART_THR  *((volatile uint8_t*)(UART_BASE + 0x00)) // Transmit Holding Register
#define UART_LSR  *((volatile uint8_t*)(UART_BASE + 0x05)) // Line Status Register

// Convolutional Tsetlin Machine Accelerator Base Address
#define ACCEL_BASE 0x30000000
#define ACCEL_REG(offset) *((volatile uint32_t*)(ACCEL_BASE + (offset)))

// Simple function to print string to UART
void print_string(const char* str) {
    while (*str) {
        // Wait for UART transmit holding register to be empty (bit 5)
        while ((UART_LSR & 0x20) == 0);
        UART_THR = *str++;
    }
}

int main() {
    print_string("Initializing Convolutional Tsetlin Machine...\n");

    // Write to Accelerator Configuration Register (Offset 0x00)
    ACCEL_REG(0x00) = 0xDEADBEEF;

    // Read from Accelerator Status Register (Offset 0x04)
    uint32_t status = ACCEL_REG(0x04);

    if (status == 0xCAFEBABE) {
        print_string("Accelerator responded correctly!\n");
    } else {
        print_string("Accelerator failed to respond.\n");
    }

    print_string("Task complete.\n");
    return 0;
}
