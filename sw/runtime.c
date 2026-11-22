// Minimal freestanding runtime: console output, plus the helpers clang
// calls because RV32I has no multiply/divide instructions.
#include <stdint.h>
#include <stddef.h>
#include "mmio.h"

void putchar_(char c) { MMIO_PUTCHAR = (uint8_t)c; }
void puts_(const char *s) { while (*s) putchar_(*s++); }

void print_uint(uint32_t v) {
    char buf[11]; int i = 0;
    do { buf[i++] = '0' + v % 10; v /= 10; } while (v);
    while (i) putchar_(buf[--i]);
}
void print_int(int32_t v) {
    if (v < 0) { putchar_('-'); print_uint(-(uint32_t)v); }
    else print_uint(v);
}
void print_hex(uint32_t v) {
    puts_("0x");
    for (int s = 28; s >= 0; s -= 4) putchar_("0123456789abcdef"[(v >> s) & 0xF]);
}

// ---- integer multiply / divide (shift-and-add, restoring division) ----
uint32_t __mulsi3(uint32_t a, uint32_t b) {
    uint32_t r = 0;
    while (b) { if (b & 1) r += a; a <<= 1; b >>= 1; }
    return r;
}
uint32_t __udivsi3(uint32_t n, uint32_t d) {
    if (d == 0) return 0xFFFFFFFF;
    uint32_t q = 0, r = 0;
    for (int i = 31; i >= 0; i--) {
        r = (r << 1) | ((n >> i) & 1);
        if (r >= d) { r -= d; q |= 1u << i; }
    }
    return q;
}
uint32_t __umodsi3(uint32_t n, uint32_t d) { return n - __mulsi3(__udivsi3(n, d), d); }
int32_t __divsi3(int32_t a, int32_t b) {
    int neg = (a < 0) ^ (b < 0);
    uint32_t q = __udivsi3(a < 0 ? -(uint32_t)a : a, b < 0 ? -(uint32_t)b : b);
    return neg ? -(int32_t)q : (int32_t)q;
}
int32_t __modsi3(int32_t a, int32_t b) { return a - (int32_t)__mulsi3(__divsi3(a, b), b); }

// clang may emit calls to these even in freestanding code
void *memset(void *d, int c, size_t n) { uint8_t *p = d; while (n--) *p++ = c; return d; }
void *memcpy(void *d, const void *s, size_t n) {
    uint8_t *p = d; const uint8_t *q = s; while (n--) *p++ = *q++; return d;
}
