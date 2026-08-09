// Simple bare-metal application controlling GPIO & UART
#define UART_BASE 0x10000000
#define GPIO_BASE 0x10002000

void main() {
    volatile char *uart = (char *)UART_BASE;
    volatile unsigned int *gpio = (unsigned int *)GPIO_BASE;

    // 1. Send 'HI' to UART 16550
    *uart = 'H';
    *uart = 'I';
    *uart = '\n';

    // 2. Drive GPIO output pins
    *gpio = 0xA5A5A5A5;

    // Infinite loop
    while (1);
}
