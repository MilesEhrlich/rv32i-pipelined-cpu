#!/bin/bash
# Compile a C program in sw/ and run it on the CPU in simulation.
#   CORE=single ./run_c.sh -> single-cycle core instead of the pipeline
#   MAX_CYCLES=10000000 ./run_c.sh digits -> longer cycle limit
#   ./run_c.sh          -> sw/hello.c
#   ./run_c.sh foo      -> sw/foo.c
set -e
PROG=${1:-hello}
DEFS=""; [ "$CORE" = single ] && DEFS="-DSINGLE_CYCLE"
[ -n "$BP" ] && DEFS="$DEFS -DBP_DEFAULT=$BP"          # BP=1: branch prediction
cd "$(dirname "$0")"
mkdir -p build
make -s -C sw PROG="$PROG"
iverilog -g2012 -o build/sim_c -P c_tb.PROGRAM=\"sw/build/$PROG.hex\" -P c_tb.MAX_CYCLES=${MAX_CYCLES:-2000000} \
    $DEFS tb/c_tb.v rtl/cpu.v rtl/cpu_pipe.v rtl/cpu_core.v rtl/bram_be.v rtl/regfile.v rtl/imm_gen.v rtl/alu.v rtl/dmem.v rtl/imem.v
vvp -n build/sim_c | grep -v readmemh
