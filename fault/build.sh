#!/bin/bash
# Build the Verilator fault-injection simulators and the programs they run:
#   baseline  build/fault/fi_sim       + sw/build/digits.hex
#   hardened  build/fault_hard/fi_sim  + sw/build/digits_hard.hex
#             (register parity; int16 biases; model checksum)
#   int16 biases only: build/fault/fi_sim + sw/build/digits_b16.hex
set -e
cd "$(dirname "$0")/.."
make -s -C sw PROG=digits
make -s -C sw PROG=digits OUT=digits_hard DEFS="-DBIAS16 -DMODEL_CHECK"
make -s -C sw PROG=digits OUT=digits_b16 DEFS="-DBIAS16"
for v in fault:0 fault_hard:1; do
    dir=${v%%:*} par=${v##*:}
    verilator --cc --exe --build -O3 -j 0 --public-flat-rw -Wno-fatal \
        --top-module cpu_core -GPARITY=$par -Mdir build/$dir -o fi_sim \
        rtl/cpu_core.v rtl/alu.v rtl/regfile.v rtl/imm_gen.v \
        fault/fi_sim.cpp > build/${dir}_build.log 2>&1 \
        || { tail -30 build/${dir}_build.log; exit 1; }
    echo "built build/$dir/fi_sim (PARITY=$par)"
done
