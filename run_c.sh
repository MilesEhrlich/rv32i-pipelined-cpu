#!/bin/bash
# Compile a C program in sw/ and run it on the CPU in simulation.
#   ./run_c.sh          -> sw/hello.c
#   ./run_c.sh foo      -> sw/foo.c
set -e
PROG=${1:-hello}
cd "$(dirname "$0")"
make -s -C sw PROG="$PROG"
iverilog -g2012 -o sim_c -P c_tb.PROGRAM=\"sw/build/$PROG.hex\" \
    c_tb.v cpu.v regfile.v imm_gen.v alu.v dmem.v imem.v
vvp -n sim_c | grep -v readmemh
