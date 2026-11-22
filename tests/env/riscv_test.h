// Bare-metal test environment for the official riscv-tests on this CPU.
// Replaces the upstream env (which relies on CSRs/traps that RV32I-only
// cores don't implement). Results are reported through the MMIO exit
// register watched by c_tb.v: 0 = pass, N = failed at test case N.
#ifndef RISCV_TEST_H
#define RISCV_TEST_H

#define TESTNUM gp

#define RVTEST_RV32U .macro init; .endm
#define RVTEST_RV64U RVTEST_RV32U

#define RVTEST_CODE_BEGIN       \
        .section .text.start;   \
        .globl _start;          \
_start:                         \
        li TESTNUM, 0;          \
        init;

#define RVTEST_CODE_END unimp

#define RVTEST_PASS             \
        fence;                  \
        li a0, 0;               \
        li t0, 0x10000004;      \
        sw a0, 0(t0);           \
1:      j 1b;

#define RVTEST_FAIL             \
        fence;                  \
        mv a0, TESTNUM;         \
        li t0, 0x10000004;      \
        sw a0, 0(t0);           \
1:      j 1b;

#define EXTRA_DATA
#define RVTEST_DATA_BEGIN EXTRA_DATA .align 4; .global begin_signature; begin_signature:
#define RVTEST_DATA_END   .align 4; .global end_signature; end_signature:

#endif
