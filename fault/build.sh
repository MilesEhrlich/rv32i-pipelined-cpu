#!/bin/bash
# Build the Verilator fault-injection simulator (build/fault/fi_sim) and the
# digits program it runs (sw/build/digits.hex).
set -e
cd "$(dirname "$0")/.."
make -s -C sw PROG=digits
verilator --cc --exe --build -O3 -j 0 --public-flat-rw -Wno-fatal \
    --top-module cpu_core -Mdir build/fault -o fi_sim \
    rtl/cpu_core.v rtl/alu.v rtl/regfile.v rtl/imm_gen.v \
    fault/fi_sim.cpp > build/fault_build.log 2>&1 \
    || { tail -30 build/fault_build.log; exit 1; }
echo "built build/fault/fi_sim"
