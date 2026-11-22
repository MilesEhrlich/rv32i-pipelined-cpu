# Measured results: single-cycle vs 5-stage pipeline

Both cores are RV32I, run the same firmware (`sw/board.c`, clang -O2), and
were measured **on the Tang Nano 9K (GW1NR-9C)** using hardware cycle and
instructions-retired counters. Cycle counts on the board match simulation exactly.

## Implementation (yosys + nextpnr-himbaechel)

| | Single-cycle (`cpu.v`) | 5-stage pipeline (`cpu_pipe.v`) |
|---|---|---|
| Clock on board | 27 MHz (oscillator) | 40.5 MHz (PLL: 27 × 3/2) |
| Fmax, seeds 1–6 | 26.1 – 28.3 MHz | 43.7 – 45.6 MHz |
| LUT4 | 2928 (33%) | 2503 (28%) |
| Flip-flops | 362 (5%) | 613 (9%) |
| Block RAM | 8 / 26 | 8 / 26 |
| riscv-tests rv32ui | 40 / 40 | 40 / 40 |

Utilization numbers include the whole system (UART, counters, I/O).

## Benchmarks (measured on hardware)

| Benchmark | Single-cycle CPI | Pipeline CPI | Single-cycle time | Pipeline time | Speedup |
|---|---|---|---|---|---|
| fib(20), recursive | 1.169 | 1.117 | 11 197 µs | 7 130 µs | **1.57×** |
| insertion sort, 200 ints | 1.145 | 1.142 | 3 261 µs | 2 169 µs | **1.50×** |
| CRC-32, 1 KB | 1.024 | 1.024 | 1 556 µs | 1 037 µs | **1.50×** |
| software mul/div | 1.004 | 1.077 | 6 708 µs | 4 796 µs | **1.40×** |

Where the extra cycles come from:

- **Single-cycle:** every load from data memory takes 2 cycles, because block
  RAM returns data one clock after the address.
- **Pipeline:** each taken branch or jump costs 1 bubble, because it's resolved
  in EX with not-taken prediction. A load immediately followed by a user of its
  result stalls 1 cycle. The mul/div benchmark spends its time in tight
  shift-and-add loops, so taken branches dominate there.

## What limited the clock, and what fixed it (pipeline)

| Step | Fmax |
|---|---|
| First working pipeline (forward load data out of MEM, no load-use stall) | 27.6 MHz |
| Forwarding selects computed in ID and registered | 28.7 MHz |
| Forward only registered values + 1-cycle load-use stall | 40.2 MHz |
| Dedicated `rs1+imm` / `pc+imm` adders (ALU mux off address/branch paths) | 44.1 MHz |

The remaining critical path is the EX loop: forwarding mux → 32-bit
compare/add → next pipeline register.

## Verification

- Official `riscv-tests` rv32ui suite (40 tests) on both cores: `./tests/run_isa_tests.sh`, `CORE=single ./tests/run_isa_tests.sh`
- Mutation checks: disabling any forwarding path, the load-use stall, the
  WB→ID bypass or branch squashing each makes the suite fail (6–40 tests).
- Full-system simulation with a UART decoder (`top_tb.v`) before every board run.
