#ifndef MMIO_H
#define MMIO_H
#include <stdint.h>
// Memory-mapped I/O registers (handled outside the CPU: testbench or FPGA top)
#define MMIO_PUTCHAR (*(volatile uint32_t *)0x10000000)  // write: output one char
#define MMIO_EXIT    (*(volatile uint32_t *)0x10000004)  // write: stop sim with code
#define MMIO_CYCLES  (*(volatile uint32_t *)0x10000008)  // read: clock cycle counter

void putchar_(char c);
void puts_(const char *s);
void print_uint(uint32_t v);
void print_int(int32_t v);
void print_hex(uint32_t v);
#endif
