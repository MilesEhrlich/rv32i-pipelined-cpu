#ifndef MMIO_H
#define MMIO_H
#include <stdint.h>
// Memory-mapped I/O registers (handled outside the CPU: c_tb.v in simulation, top.v on the board)
#define MMIO_PUTCHAR (*(volatile uint32_t *)0x10000000)  // write: send one char (UART)
#define MMIO_EXIT    (*(volatile uint32_t *)0x10000004)  // write: stop sim with code (sim only)
#define MMIO_CYCLES  (*(volatile uint32_t *)0x10000008)  // read: clock cycle counter
#define MMIO_LEDS    (*(volatile uint32_t *)0x1000000C)  // read/write: 6 LEDs, 1 = on
#define MMIO_UART_ST (*(volatile uint32_t *)0x10000010)  // read: bit 0 = UART busy
#define MMIO_BUTTONS (*(volatile uint32_t *)0x10000014)  // read: bit 0 = S1, bit 1 = S2

#define CLOCK_HZ 27000000u

void putchar_(char c);
void puts_(const char *s);
void print_uint(uint32_t v);
void print_int(int32_t v);
void print_hex(uint32_t v);
void delay_cycles(uint32_t n);
#endif
