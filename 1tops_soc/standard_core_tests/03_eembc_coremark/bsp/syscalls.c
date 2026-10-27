#include <stdarg.h>
#include <stdint.h>
#include <stddef.h>

#define CONSOLE_OUT_ADDR 0x80001000
#define TOHOST_ADDR      0x80001004

uint32_t rdcycle(void) {
    uint32_t c;
    __asm__ volatile ("csrr %0, cycle" : "=r"(c));
    return c;
}

uint32_t rdinstret(void) {
    uint32_t i;
    __asm__ volatile ("csrr %0, instret" : "=r"(i));
    return i;
}

void tohost_exit(int code) {
    *(volatile uint32_t*)TOHOST_ADDR = (uint32_t)code;
    while (1);
}

void exit(int code) {
    tohost_exit(code);
}

void abort(void) {
    tohost_exit(1);
}

int putchar(int c) {
    *(volatile uint32_t*)CONSOLE_OUT_ADDR = (uint32_t)c;
    return c;
}

int puts(const char *s) {
    while (*s) {
        putchar(*s++);
    }
    putchar('\n');
    return 0;
}

__attribute__((optimize("no-tree-loop-distribute-patterns")))
void* memcpy(void *dest, const void *src, size_t n) {
    char *d = (char*)dest;
    const char *s = (const char*)src;
    while (n--) {
        *d++ = *s++;
    }
    return dest;
}

__attribute__((optimize("no-tree-loop-distribute-patterns")))
void* memset(void *s, int c, size_t n) {
    volatile unsigned char *p = (volatile unsigned char*)s;
    while (n--) {
        *p++ = (unsigned char)c;
    }
    return s;
}

size_t strlen(const char *s) {
    const char *p = s;
    while (*p) p++;
    return (size_t)(p - s);
}

int strcmp(const char *s1, const char *s2) {
    while (*s1 && (*s1 == *s2)) {
        s1++;
        s2++;
    }
    return *(const unsigned char*)s1 - *(const unsigned char*)s2;
}

static void print_unsigned(uint32_t n, int base) {
    char buf[32];
    int i = 0;
    const char digits[] = "0123456789abcdef";
    if (n == 0) {
        putchar('0');
        return;
    }
    while (n > 0) {
        buf[i++] = digits[n % base];
        n /= base;
    }
    while (i > 0) {
        putchar(buf[--i]);
    }
}

static void print_signed(int32_t n) {
    if (n < 0) {
        putchar('-');
        n = -n;
    }
    print_unsigned((uint32_t)n, 10);
}

int printf(const char *fmt, ...) {
    va_list va;
    va_start(va, fmt);
    while (*fmt) {
        if (*fmt == '%') {
            fmt++;
            if (*fmt == '\0') break;
            
            int zero_pad = 0;
            int width = 0;
            if (*fmt == '0') {
                zero_pad = 1;
                fmt++;
            }
            while (*fmt >= '0' && *fmt <= '9') {
                width = width * 10 + (*fmt - '0');
                fmt++;
            }
            if (*fmt == 'l') fmt++; // skip long
            
            switch (*fmt) {
                case 'd':
                case 'i': {
                    int val = va_arg(va, int);
                    print_signed(val);
                    break;
                }
                case 'u': {
                    unsigned int val = va_arg(va, unsigned int);
                    print_unsigned(val, 10);
                    break;
                }
                case 'x':
                case 'X': {
                    unsigned int val = va_arg(va, unsigned int);
                    print_unsigned(val, 16);
                    break;
                }
                case 's': {
                    const char *s = va_arg(va, const char*);
                    if (!s) s = "(null)";
                    while (*s) putchar(*s++);
                    break;
                }
                case 'c': {
                    char c = (char)va_arg(va, int);
                    putchar(c);
                    break;
                }
                case '%': {
                    putchar('%');
                    break;
                }
                default:
                    putchar('%');
                    putchar(*fmt);
                    break;
            }
        } else {
            putchar(*fmt);
        }
        fmt++;
    }
    va_end(va);
    return 0;
}
