#!/bin/bash
# Build the board fault-injection system (rtl/fi_top.v) and load it.
#   fault/build_board.sh base   -> baseline core + sw/digits.c
#   fault/build_board.sh hard   -> PARITY=1 core + hardened digits (int16, checksum)
#   NOLOAD=1 fault/build_board.sh base   -> build only
# Then collect trials with fault/board_fi.py.
set -e
V=${1:-base}
cd "$(dirname "$0")/.."
case $V in
    base) PROG=digits;      PAR=0; make -s -C sw PROG=digits ;;
    hard) PROG=digits_hard; PAR=1; make -s -C sw PROG=digits OUT=digits_hard DEFS="-DBIAS16 -DMODEL_CHECK" ;;
    *) echo "variant: base or hard"; exit 1 ;;
esac
TE=$(/opt/homebrew/opt/llvm/bin/llvm-objdump -h sw/build/$PROG.elf | python3 -c "
import sys
for l in sys.stdin:
    p = l.split()
    if len(p) >= 4 and p[1] == '.text': print(int(p[3], 16) + int(p[2], 16))")
mkdir -p reports build
RTL="rtl/fi_top.v rtl/cpu_core.v rtl/regfile.v rtl/alu.v rtl/imm_gen.v rtl/imem.v rtl/bram_be.v rtl/uart_tx.v"
yosys -p "read_verilog -DSYNTHESIS -DFI_PORTS $RTL; chparam -set PROGRAM \"sw/build/$PROG.hex\" -set PARITY $PAR -set TEXT_END $TE fi_top; synth_gowin -top fi_top -json build/fi_$V.json" \
    > reports/fi_yosys_$V.log 2>&1 || { tail -20 reports/fi_yosys_$V.log; exit 1; }
nextpnr-himbaechel --json build/fi_$V.json --write build/fi_${V}_pnr.json \
    --device GW1NR-LV9QN88PC6/I5 --vopt family=GW1N-9C --vopt cst=constraints/soc.cst \
    --freq 27 --seed ${SEED:-1} > reports/fi_nextpnr_$V.log 2>&1 || { grep -E "ERROR" reports/fi_nextpnr_$V.log; exit 1; }
echo "---- $V: timing / utilisation ----"
grep "Max frequency for clock" reports/fi_nextpnr_$V.log | tail -1 | sed 's/^Info: *//'
grep -A16 "Device utilisation" reports/fi_nextpnr_$V.log | grep -E ' (LUT4|DFF|RAM16SDP4|BSRAM):' | sed 's/^Info: *//'
gowin_pack -d GW1N-9C -o build/fi_$V.fs build/fi_${V}_pnr.json 2>&1 | grep -vE 'not available|warnings.warn' || true
[ -n "$NOLOAD" ] || openFPGALoader -b tangnano9k build/fi_$V.fs
