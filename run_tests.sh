#!/bin/bash
# Run every simulation test, on both cores (pipeline with and without branch prediction). Prints one line per suite.
#   ./run_tests.sh
cd "$(dirname "$0")"
mkdir -p build
CORE_RTL="rtl/cpu.v rtl/cpu_pipe.v rtl/cpu_core.v rtl/bram_be.v rtl/regfile.v rtl/imm_gen.v rtl/alu.v rtl/dmem.v rtl/imem.v"
fails=0

check() {  # check "name" "expected text" command...
    local name=$1 want=$2; shift 2
    if out=$("$@" 2>&1) && echo "$out" | grep -q "$want"; then
        printf "  PASS  %s\n" "$name"
    else
        printf "  FAIL  %s\n" "$name"
        # every failing line, plus the tail, so the cause is kept
        { echo "$out" | grep -iE "fail|error|timeout" | head -20; echo "$out" | tail -3; } | sed 's/^/        /'
        fails=$((fails+1))
    fi
}
sim() { iverilog -g2012 -o build/t "$@" && vvp -n build/t; }

check "4-bit adder (exhaustive)"      "All 256 tests passed"  sim learning/adder_tb.v learning/adder.v
check "CPU parts (regfile/imm/ALU/mem)" "All parts tests passed" sim tb/parts_tb.v rtl/regfile.v rtl/imm_gen.v rtl/alu.v rtl/dmem.v
check "single-cycle: hand-assembled program" "CPU test passed"  sim tb/cpu_tb.v $CORE_RTL
for core in pipe pipe+bp single; do       # pipe+bp: pipeline with branch prediction
    c=${core%+bp}; bp=0; [ $core = pipe+bp ] && bp=1
    check "$core: riscv-tests rv32ui"   "40 passed, 0 failed"   env CORE=$c BP=$bp ./tests/run_isa_tests.sh
    check "$core: C program (hello.c)"  "C TEST PASSED"         env CORE=$c BP=$bp ./run_c.sh hello
    D="-DBP_DEFAULT=$bp"; [ $core = single ] && D=-DSINGLE_CYCLE
    check "$core: full system + UART (board.c)" "muldiv    ok" \
        sim $D tb/top_tb.v rtl/top.v rtl/uart_tx.v $CORE_RTL
done

echo
[ $fails -eq 0 ] && echo "All suites passed." || { echo "$fails suite(s) failed."; exit 1; }
