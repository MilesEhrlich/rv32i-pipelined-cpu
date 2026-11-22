// Board demo + benchmark. Runs a few workloads and reports, for each, the
// cycles, instructions retired, CPI and wall-clock time, read from the
// hardware counters. Then counts on the LEDs forever.
// Hold S2 to count faster; press S1 to reset the CPU.
#include "mmio.h"

static int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }

#define N_SORT 200
static int arr[N_SORT];
static void sort(int *a, int n) {                 // insertion sort
    for (int i = 1; i < n; i++) {
        int k = a[i], j = i - 1;
        while (j >= 0 && a[j] > k) { a[j + 1] = a[j]; j--; }
        a[j + 1] = k;
    }
}

static uint8_t buf[1024];
static uint32_t crc32(const uint8_t *p, int n) {
    uint32_t c = 0xFFFFFFFF;
    for (int i = 0; i < n; i++) {
        c ^= p[i];
        for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320 & -(c & 1));
    }
    return ~c;
}

static uint32_t muldiv(void) {
    uint32_t acc = 1;
    for (volatile uint32_t i = 1; i < 200; i++) acc = acc * 2654435761u / i + i % 7;
    return acc;
}

static uint32_t c0, i0;
static void start(void) { i0 = MMIO_INSTRET; c0 = MMIO_CYCLES; }
static void report(const char *name, uint32_t result, uint32_t expect) {
    uint32_t c = MMIO_CYCLES - c0, n = MMIO_INSTRET - i0;
    // 32-bit math is exact while c < ~4.2 million cycles
    uint32_t cpi1000 = c * 1000 / n;
    uint32_t us = c * 1000 / (MMIO_CLK_HZ / 1000);
    puts_(name);
    puts_(result == expect ? " ok " : " WRONG ");
    puts_(" cycles "); print_uint(c);
    puts_("  instr "); print_uint(n);
    puts_("  CPI "); print_uint(cpi1000 / 1000); putchar_('.');
    putchar_('0' + cpi1000 / 100 % 10); putchar_('0' + cpi1000 / 10 % 10); putchar_('0' + cpi1000 % 10);
    puts_("  time "); print_uint(us); puts_(" us\r\n");
}

int main(void) {
    puts_("\r\nHello from my RISC-V CPU on the Tang Nano 9K!\r\n");
    puts_("clock "); print_uint(MMIO_CLK_HZ); puts_(" Hz\r\n");

    start(); int f = fib(20); report("fib(20)  ", f, 6765);

    uint32_t x = 12345;
    for (int i = 0; i < N_SORT; i++) { x = x * 1103515245u + 12345u; arr[i] = (int)(x >> 8) % 1000; }
    start(); sort(arr, N_SORT);
    uint32_t sorted = 1;
    for (int i = 1; i < N_SORT; i++) if (arr[i - 1] > arr[i]) sorted = 0;
    report("sort(200)", sorted, 1);

    for (int i = 0; i < 1024; i++) buf[i] = (uint8_t)(i * 7 + 3);
    start(); uint32_t crc = crc32(buf, 1024); report("crc32(1K)", crc, 0x5D3DE8ED);      // zlib.crc32 reference

    start(); uint32_t md = muldiv(); report("muldiv   ", md, 14905503);          // computed in Python

    for (uint32_t n = 0;; n++) {
        MMIO_LEDS = n;
        puts_("count "); print_uint(n);
        puts_("  buttons "); print_hex(MMIO_BUTTONS);
        puts_("\r\n");
        delay_cycles((MMIO_BUTTONS & 2) ? MMIO_CLK_HZ / 20 : MMIO_CLK_HZ / 2);
    }
}
