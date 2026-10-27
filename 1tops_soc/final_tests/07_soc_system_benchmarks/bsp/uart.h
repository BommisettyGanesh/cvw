#ifndef UART_H
#define UART_H

#include <stdint.h>
#include <stddef.h>

#define UART_BASE 0x10000000
#define UART_THR  (*(volatile uint8_t*)(UART_BASE + 0x00))
#define UART_LSR  (*(volatile uint8_t*)(UART_BASE + 0x05))

#define UART_LSR_THRE 0x20

extern volatile uint32_t tohost;

static inline void uart_init(void) {
    // 16550 UART dummy init
}

static inline void uart_putc(char c) {
    while (!(UART_LSR & UART_LSR_THRE))
        ;
    UART_THR = (uint8_t)c;
}

static inline void uart_puts(const char *s) {
    while (*s) {
        if (*s == '\n') {
            uart_putc('\r');
        }
        uart_putc(*s++);
    }
}

static inline uint32_t rdcycle(void) {
    uint32_t cycles;
    asm volatile ("rdcycle %0" : "=r" (cycles));
    return cycles;
}

static inline uint32_t rdinstret(void) {
    uint32_t insts;
    asm volatile ("rdinstret %0" : "=r" (insts));
    return insts;
}

static inline uint64_t rdcycle64(void) {
    uint32_t cycles_lo, cycles_hi, cycles_hi2;
    do {
        asm volatile ("rdcycleh %0" : "=r" (cycles_hi));
        asm volatile ("rdcycle %0"  : "=r" (cycles_lo));
        asm volatile ("rdcycleh %0" : "=r" (cycles_hi2));
    } while (cycles_hi != cycles_hi2);
    return (((uint64_t)cycles_hi) << 32) | cycles_lo;
}

static inline uint64_t rdinstret64(void) {
    uint32_t inst_lo, inst_hi, inst_hi2;
    do {
        asm volatile ("rdinstreth %0" : "=r" (inst_hi));
        asm volatile ("rdinstret %0"  : "=r" (inst_lo));
        asm volatile ("rdinstreth %0" : "=r" (inst_hi2));
    } while (inst_hi != inst_hi2);
    return (((uint64_t)inst_hi) << 32) | inst_lo;
}

static inline void tohost_exit(int code) {
    tohost = (code << 1) | 1;
    while (1) {
        asm volatile ("wfi");
    }
}

#endif // UART_H
