#!/bin/bash
# Build the CPU system (top.v) with a C program and load it onto the Tang Nano 9K.
#   ./build_soc.sh            -> sw/board.c
#   ./build_soc.sh foo        -> sw/foo.c
#   NOLOAD=1 ./build_soc.sh   -> build + reports only, don't touch the board
#   CORE=single ./build_soc.sh -> single-cycle core instead of the pipeline
#   SEED=n ./build_soc.sh       -> place-and-route seed (results vary slightly)
# Reports land in reports/ (yosys.log, nextpnr.log); a summary is printed.
set -e
PROG=${1:-board}
DEFS=""; FREQ=40.5
[ "$CORE" = single ] && { DEFS="-DSINGLE_CYCLE"; FREQ=27; }
cd "$(dirname "$0")"
mkdir -p reports
RTL="top.v uart_tx.v cpu.v cpu_pipe.v regfile.v imm_gen.v alu.v dmem.v imem.v"

make -s -C sw PROG="$PROG"
yosys -p "read_verilog -DSYNTHESIS $DEFS $RTL; chparam -set PROGRAM \"sw/build/$PROG.hex\" top; synth_gowin -top top -json build.json" \
    > reports/yosys.log 2>&1 || { tail -20 reports/yosys.log; exit 1; }
nextpnr-himbaechel --json build.json --write pnr.json \
    --device GW1NR-LV9QN88PC6/I5 --vopt family=GW1N-9C --vopt cst=soc.cst \
    --freq $FREQ --seed ${SEED:-1} > reports/nextpnr.log 2>&1 || { grep -E "ERROR" reports/nextpnr.log; exit 1; }

echo "---- timing ----"
grep "Max frequency for clock" reports/nextpnr.log | tail -2 | sed 's/^Info: *//'
echo "---- utilisation ----"
grep -A16 "Device utilisation" reports/nextpnr.log | grep -E ' (LUT4|DFF|ALU|RAM16SDP4|BSRAM):' | sed 's/^Info: *//'

gowin_pack -d GW1N-9C -o build.fs pnr.json 2>/dev/null
[ -n "$NOLOAD" ] || openFPGALoader -b tangnano9k build.fs
