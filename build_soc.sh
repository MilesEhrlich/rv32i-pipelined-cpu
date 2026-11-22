#!/bin/bash
# Build the CPU system (rtl/top.v) with a C program and load it onto the Tang Nano 9K.
#   ./build_soc.sh            -> sw/board.c
#   ./build_soc.sh foo        -> sw/foo.c
#   NOLOAD=1 ./build_soc.sh   -> build + reports only, don't touch the board
#   CORE=single ./build_soc.sh -> single-cycle core instead of the pipeline
#   SEED=n ./build_soc.sh       -> place-and-route seed (results vary slightly)
#   BP=1 ./build_soc.sh         -> pipeline with branch prediction
# Reports land in reports/ (yosys.log, nextpnr.log); a summary is printed.
set -e
PROG=${1:-board}
DEFS=""; FREQ=40.5
[ "$CORE" = single ] && { DEFS="-DSINGLE_CYCLE"; FREQ=27; SEED=${SEED:-5}; }  # single-cycle is at the edge of 27 MHz; seed 5 passes
[ -n "$BP" ] && DEFS="$DEFS -DBP_DEFAULT=$BP"              # BP=1: pipeline with branch prediction
cd "$(dirname "$0")"
mkdir -p reports build
RTL="rtl/top.v rtl/uart_tx.v rtl/cpu.v rtl/cpu_pipe.v rtl/cpu_core.v rtl/bram_be.v rtl/regfile.v rtl/imm_gen.v rtl/alu.v rtl/dmem.v rtl/imem.v"

make -s -C sw PROG="$PROG"
yosys -p "read_verilog -DSYNTHESIS $DEFS $RTL; chparam -set PROGRAM \"sw/build/$PROG.hex\" top; synth_gowin -top top -json build/soc.json" \
    > reports/yosys.log 2>&1 || { tail -20 reports/yosys.log; exit 1; }
nextpnr-himbaechel --json build/soc.json --write build/soc_pnr.json \
    --device GW1NR-LV9QN88PC6/I5 --vopt family=GW1N-9C --vopt cst=constraints/soc.cst \
    --freq $FREQ --seed ${SEED:-1} > reports/nextpnr.log 2>&1 || { grep -E "ERROR" reports/nextpnr.log; exit 1; }

echo "---- timing ----"
grep "Max frequency for clock" reports/nextpnr.log | tail -2 | sed 's/^Info: *//'
echo "---- utilisation ----"
grep -A16 "Device utilisation" reports/nextpnr.log | grep -E ' (LUT4|DFF|ALU|RAM16SDP4|BSRAM):' | sed 's/^Info: *//'

# gowin_pack warns about optional speed-up packages; show anything else
gowin_pack -d GW1N-9C -o build/soc.fs build/soc_pnr.json 2>&1 | grep -vE 'not available|warnings.warn' || true
[ -f build/soc.fs ] || { echo "gowin_pack failed"; exit 1; }
[ -n "$NOLOAD" ] || openFPGALoader -b tangnano9k build/soc.fs
