#!/bin/bash
set -e
yosys -q -p "read_verilog $1; synth_gowin -top top -json build.json"
nextpnr-himbaechel -q --json build.json --write pnr.json \
  --device GW1NR-LV9QN88PC6/I5 \
  --vopt family=GW1N-9C --vopt cst=tangnano9k.cst
gowin_pack -d GW1N-9C -o build.fs pnr.json
openFPGALoader -b tangnano9k build.fs