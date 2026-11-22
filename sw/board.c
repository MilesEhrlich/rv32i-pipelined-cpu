// Board demo: greets over UART, then counts on the LEDs forever while
// reporting progress. Hold S2 to count faster; press S1 to reset the CPU.
#include "mmio.h"

static int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }

int main(void) {
    puts_("\r\nHello from my RISC-V CPU on the Tang Nano 9K!\r\n");

    uint32_t t0 = MMIO_CYCLES;
    int f = fib(20);
    uint32_t dt = MMIO_CYCLES - t0;
    puts_("fib(20) = "); print_int(f);
    puts_(" in "); print_uint(dt); puts_(" cycles\r\n");

    for (uint32_t n = 0;; n++) {
        MMIO_LEDS = n;
        puts_("count "); print_uint(n);
        puts_("  buttons "); print_hex(MMIO_BUTTONS);
        puts_("\r\n");
        delay_cycles((MMIO_BUTTONS & 2) ? CLOCK_HZ / 20 : CLOCK_HZ / 2);
    }
}
