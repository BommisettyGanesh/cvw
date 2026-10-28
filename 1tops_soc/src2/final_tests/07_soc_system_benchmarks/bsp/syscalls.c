/* =============================================================================
 * Minimal C Runtime & Formatted Printing for RISC-V Bare-Metal System
 * ============================================================================= */

#include "uart.h"
#include <stdarg.h>
#include <stdint.h>
#include <stddef.h>

void exit(int code) {
    tohost_exit(code);
    while (1);
}

void abort(void) {
    tohost_exit(1);
    while (1);
}

int putchar(int c) {
    if (c == '\n') {
        uart_putc('\r');
    }
    uart_putc((char)c);
    return c;
}

int puts(const char *s) {
    uart_puts(s);
    uart_putc('\r');
    uart_putc('\n');
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

static void print_num(void (*put_func)(char, void*), void *ctx, uint32_t u, int base, int width, char pad, int sign) {
    char buf[36];
    int idx = 0;
    const char digits[] = "0123456789abcdef";

    if (sign && ((int32_t)u < 0)) {
        put_func('-', ctx);
        u = (uint32_t)(-(int32_t)u);
        if (width > 0) width--;
    }

    if (u == 0) {
        buf[idx++] = '0';
    } else {
        while (u > 0) {
            buf[idx++] = digits[u % base];
            u /= base;
        }
    }

    while (width > idx) {
        put_func(pad, ctx);
        width--;
    }

    while (idx > 0) {
        put_func(buf[--idx], ctx);
    }
}

typedef struct {
    char *buf;
    size_t max;
    size_t count;
} str_buf_t;

static void uart_put_adapter(char c, void *ctx) {
    (void)ctx;
    putchar(c);
}

static void str_put_adapter(char c, void *ctx) {
    str_buf_t *sb = (str_buf_t*)ctx;
    if (sb->count + 1 < sb->max) {
        sb->buf[sb->count++] = c;
    }
}

static int vxprintf(void (*put_func)(char, void*), void *ctx, const char *fmt, va_list ap) {
    const char *p = fmt;
    while (*p) {
        if (*p != '%') {
            put_func(*p++, ctx);
            continue;
        }
        p++; // skip '%'

        char pad = ' ';
        if (*p == '0') {
            pad = '0';
            p++;
        }

        int width = 0;
        while (*p >= '0' && *p <= '9') {
            width = width * 10 + (*p - '0');
            p++;
        }

        if (*p == 'l') {
            p++; // Ignore long modifier for 32-bit RV32
        }

        switch (*p) {
            case 'd':
            case 'i': {
                int32_t val = va_arg(ap, int32_t);
                print_num(put_func, ctx, (uint32_t)val, 10, width, pad, 1);
                break;
            }
            case 'u': {
                uint32_t val = va_arg(ap, uint32_t);
                print_num(put_func, ctx, val, 10, width, pad, 0);
                break;
            }
            case 'x':
            case 'p': {
                uint32_t val = va_arg(ap, uint32_t);
                print_num(put_func, ctx, val, 16, width, pad, 0);
                break;
            }
            case 'c': {
                char val = (char)va_arg(ap, int);
                put_func(val, ctx);
                break;
            }
            case 's': {
                const char *s = va_arg(ap, const char*);
                if (!s) s = "(null)";
                int len = (int)strlen(s);
                while (width > len) {
                    put_func(pad, ctx);
                    width--;
                }
                while (*s) {
                    put_func(*s++, ctx);
                }
                break;
            }
            case '%': {
                put_func('%', ctx);
                break;
            }
            default: {
                put_func('%', ctx);
                put_func(*p, ctx);
                break;
            }
        }
        if (*p) p++;
    }
    return 0;
}

int printf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int ret = vxprintf(uart_put_adapter, NULL, fmt, ap);
    va_end(ap);
    return ret;
}

int sprintf(char *str, const char *fmt, ...) {
    str_buf_t sb = { str, 65536, 0 };
    va_list ap;
    va_start(ap, fmt);
    int ret = vxprintf(str_put_adapter, &sb, fmt, ap);
    va_end(ap);
    sb.buf[sb.count] = '\0';
    return ret;
}
