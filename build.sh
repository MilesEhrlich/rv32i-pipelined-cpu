#!/bin/bash
# Build a standalone design (module `top`) and load it onto the Tang Nano 9K.
#   ./build.sh learning/blink.v
#   CST=constraints/soc.cst ./build.sh ...   -> different pin file
set -e
cd "$(dirname "$0")"
mkdir -p build
yosys -q -p "read_verilog $*; synth_gowin -top top -json build/design.json"
nextpnr-himbaechel -q --json build/design.json --write build/design_pnr.json \
  --device GW1NR-LV9QN88PC6/I5 \
  --vopt family=GW1N-9C --vopt cst=${CST:-constraints/tangnano9k.cst}
gowin_pack -d GW1N-9C -o build/design.fs build/design_pnr.json
openFPGALoader -b tangnano9k build/design.fs
