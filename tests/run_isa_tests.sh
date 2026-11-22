#!/bin/bash
# Build every official rv32ui test from riscv-tests and run it on the CPU in simulation.
#   ./tests/run_isa_tests.sh          -> run all
#   ./tests/run_isa_tests.sh add beq  -> run just those
#   CORE=single ./tests/run_isa_tests.sh -> single-cycle core
# Fetch the test sources once with:  git submodule update --init tests/upstream
DEFS=""; [ "$CORE" = single ] && DEFS="-DSINGLE_CYCLE"
cd "$(dirname "$0")/.."
LLVM=/opt/homebrew/opt/llvm/bin
LLD=/opt/homebrew/opt/lld/bin
ISA=tests/upstream/isa
OUT=tests/build
mkdir -p "$OUT"

# fence_i: needs self-modifying code (imem is read-only, Harvard)
# ma_data: misaligned accesses (optional in RV32I; we don't support them)
SKIP="fence_i ma_data"

if [ $# -gt 0 ]; then TESTS="$*"; else
    TESTS=$(ls $ISA/rv32ui/*.S | xargs -n1 basename | sed 's/\.S$//')
fi

pass=0; fail=0; failed=""
for t in $TESTS; do
    case " $SKIP " in *" $t "*) printf "%-8s skipped\n" "$t"; continue;; esac
    $LLVM/clang --target=riscv32-unknown-elf -march=rv32i -mabi=ilp32 -nostdlib \
        -mno-relax -fuse-ld=$LLD/ld.lld -T sw/link.ld \
        -I tests/env -I $ISA/macros/scalar \
        -o $OUT/$t.elf $ISA/rv32ui/$t.S || { fail=$((fail+1)); failed="$failed $t"; continue; }
    $LLVM/llvm-objcopy -O binary $OUT/$t.elf $OUT/$t.bin
    python3 sw/bin2hex.py $OUT/$t.bin $OUT/$t.hex
    $LLVM/llvm-objdump -d $OUT/$t.elf > $OUT/$t.dis
    rm -f $OUT/sim
    if ! iverilog -g2012 -o $OUT/sim -P c_tb.PROGRAM=\"$OUT/$t.hex\" -P c_tb.MAX_CYCLES=100000 \
            $DEFS tb/c_tb.v rtl/cpu.v rtl/cpu_pipe.v rtl/regfile.v rtl/imm_gen.v rtl/alu.v rtl/dmem.v rtl/imem.v; then
        printf "%-8s FAIL  (Verilog compile error)\n" "$t"
        fail=$((fail+1)); failed="$failed $t"; continue
    fi
    result=$(vvp -n $OUT/sim | grep -v readmemh)
    if echo "$result" | grep -q "C TEST PASSED"; then
        printf "%-8s PASS\n" "$t"; pass=$((pass+1))
    else
        printf "%-8s FAIL  %s\n" "$t" "$(echo "$result" | grep -E 'exited|timeout' | head -1)"
        fail=$((fail+1)); failed="$failed $t"
    fi
done
echo "----------------------------------------"
echo "$pass passed, $fail failed${failed:+:$failed}"
[ $fail -eq 0 ]
