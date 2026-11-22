# Measured results: single-cycle vs 5-stage pipeline

Both cores are RV32I, run the same firmware (`sw/board.c`, clang -O2), and
were measured **on the Tang Nano 9K (GW1NR-9C)** using hardware cycle and
instructions-retired counters. Cycle counts on the board match simulation exactly.

## Implementation (yosys + nextpnr-himbaechel)

| | Single-cycle (`cpu.v`) | 5-stage pipeline (`cpu_pipe.v`) |
|---|---|---|
| Clock on board | 27 MHz (oscillator) | 40.5 MHz (PLL: 27 × 3/2) |
| Fmax, seeds 1–6 | 26.3 – 27.1 MHz | 44.3 – 45.4 MHz |
| LUT4 | 3040 (35%) | 2859 (33%) |
| Flip-flops | 362 (5%) | 613 (9%) |
| Block RAM | 8 / 26 | 8 / 26 |
| riscv-tests rv32ui | 40 / 40 | 40 / 40 |

Utilization numbers include the whole system (UART, counters, I/O).

These numbers move between builds. Place-and-route seeds change Fmax by a few
percent, and even renaming files changed yosys's logic mapping: the same
pipeline went from 2503 to 2859 LUTs, and 44.5 to 45.2 MHz, after the repo was
reorganized. The single-cycle core is right at the edge of 27 MHz (only some
seeds pass), so `build_soc.sh` uses a seed that passes for it. The benchmark
timings below don't depend on any of this: cycle counts are fixed by the
design, and the clock rates are set by the oscillator and PLL.

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

## Branch prediction (`BP=1`)

A 16-entry branch target buffer with 2-bit counters, looked up with the PC of
the instruction in ID: that is the cycle in which the next fetch address is
chosen, so a correctly predicted taken branch or `jal` costs nothing instead
of 1 cycle. `jalr` is not predicted. Off by default (`BP=1 ./build_soc.sh`,
`BP=1 ./run_c.sh`, and `run_tests.sh` covers both), so the ASIC and fault
study keep describing the core they measured.

| Benchmark (board, 40.5 MHz) | Pipeline | + branch prediction | Change |
|---|---|---|---|
| fib(20), recursive | 288 797 cycles, 7 130 µs | 291 381 cycles, 7 194 µs | **+0.9%** |
| insertion sort, 200 ints | 87 869 cycles, 2 169 µs | 77 297 cycles, 1 908 µs | **−12.0%** |
| CRC-32, 1 KB | 42 017 cycles, 1 037 µs | 40 996 cycles, 1 012 µs | **−2.4%** |
| software mul/div | 194 254 cycles, 4 796 µs | 181 920 cycles, 4 491 µs | **−6.4%** |
| int8 neural network, per image (sim) | 65 105 cycles | 61 493 cycles | **−5.5%** |

| | Pipeline | + branch prediction |
|---|---|---|
| Fmax, seeds 1–3 | 43.0 – 43.8 MHz | 41.8 – 42.8 MHz |
| LUT4 | 2671 | 3177 (+506) |
| Flip-flops | – | 669 |

- Sort, CRC and mul/div now run at CPI 1.005, 0.999 and 1.008: almost every
  remaining bubble is a load-use stall or a `jalr`.
- **fib gets slightly worse.** Its returns are `jalr` (not predicted), and
  its `n < 2` branch changes direction in a pattern a 2-bit counter keeps
  mispredicting, where static not-taken was right more often. A return
  address stack would fix the first part.
- BTB size makes no difference here: 8 to 64 entries give the same cycles
  (except muldiv, +0.2% with 8), so 16 is enough for these loops.
- It still meets 40.5 MHz on every seed (about 3% lower Fmax), so on the
  board the cycles saved are time saved.
- Cycle counts on the board match simulation exactly, as for the other cores.

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

## ASIC (SkyWater 130 nm, LibreLane)

The pipeline core (`cpu_core.v`, memories external) hardened to a signed-off
layout. Details and the full clock sweep are in [asic/README.md](asic/README.md).

| | FPGA (GW1NR-9) | ASIC (sky130, typical corner) |
|---|---|---|
| Clock | 40.5 MHz (Fmax ~45 MHz) | 90.9 MHz (slow corner ~61 MHz) |
| Size | 2 859 LUT4 + 613 FFs (system) | 0.19 mm² die, 11 685 cells (core) |
| Power | — | 12.7 mW at 90.9 MHz (estimated) |
