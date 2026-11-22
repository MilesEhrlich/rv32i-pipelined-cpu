#!/bin/bash
# Compile a C program in sw/ and run it on the CPU in simulation.
#   CORE=single ./run_c.sh -> single-cycle core instead of the pipeline
#   ./run_c.sh          -> sw/hello.c
#   ./run_c.sh foo      -> sw/foo.c
set -e
PROG=${1:-hello}
DEFS=""; [ "$CORE" = single ] && DEFS="-DSINGLE_CYCLE"
cd "$(dirname "$0")"
mkdir -p build
make -s -C sw PROG="$PROG"
iverilog -g2012 -o build/sim_c -P c_tb.PROGRAM=\"sw/build/$PROG.hex\" \
    $DEFS tb/c_tb.v rtl/cpu.v rtl/cpu_pipe.v rtl/cpu_core.v rtl/bram_be.v rtl/regfile.v rtl/imm_gen.v rtl/alu.v rtl/dmem.v rtl/imem.v
vvp -n build/sim_c | grep -v readmemh
