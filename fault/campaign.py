#!/usr/bin/env python3
"""Run single-bit fault-injection campaigns on the pipelined core.

For each target structure, runs N random trials with build/fault/fi_sim
(split across worker processes), saves raw results to fault/results/<target>.csv
and prints an outcome summary with 95% confidence intervals.

    fault/build.sh
    ~/.venvs/rv32i-ml/bin/python fault/campaign.py              # all targets, 3000 trials each
    ~/.venvs/rv32i-ml/bin/python fault/campaign.py --trials 500 --targets regfile pc
"""
import argparse, csv, io, math, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIM = os.path.join(REPO, "build/fault/fi_sim")
ELF = os.path.join(REPO, "sw/build/digits.elf")
HEX = os.path.join(REPO, "sw/build/digits.hex")
LLVM = "/opt/homebrew/opt/llvm/bin"
OUTCOMES = ["masked", "tolerated", "sdc", "crash"]


def symbols():
    out = subprocess.run([f"{LLVM}/llvm-nm", "-S", ELF], capture_output=True, text=True, check=True).stdout
    syms = {}
    for line in out.splitlines():
        p = line.split()
        if len(p) == 4:
            syms[p[3]] = (int(p[0], 16), int(p[1], 16))
    hdr = subprocess.run([f"{LLVM}/llvm-objdump", "-h", ELF], capture_output=True, text=True, check=True).stdout
    for line in hdr.splitlines():
        p = line.split()
        if len(p) >= 4 and p[1] == ".text":
            syms[".text"] = (int(p[3], 16), int(p[2], 16))
    return syms


def targets(syms):
    t0, tlen = syms[".text"]
    w1, w2, b1, b2 = (syms[k] for k in ("W1", "W2", "b1", "b2"))
    # name -> (fi_sim arguments, description)
    return {
        "regfile":  ([f"target=regfile"], "general-purpose registers x1-x31"),
        "pc":       ([f"target=pc"], "program counter (instruction in ID)"),
        "id_ex":    ([f"target=id_ex"], "ID/EX pipeline register"),
        "ex_mem":   ([f"target=ex_mem"], "EX/MEM pipeline register"),
        "mem_wb":   ([f"target=mem_wb"], "MEM/WB pipeline register"),
        "instr":    ([f"target=instr"], "fetched instruction word (IF/ID)"),
        "ldata":    ([f"target=ldata"], "loaded data word"),
        "code":     ([f"target=imem", f"region={t0}:{tlen}", "at=start"], "instruction memory (program code)"),
        "W1":       ([f"target=dmem", f"region={w1[0]}:{w1[1]}", "at=start"], "layer-1 weights in data memory"),
        "W2":       ([f"target=dmem", f"region={w2[0]}:{w2[1]}", "at=start"], "layer-2 weights in data memory"),
        "biases":   ([f"target=dmem", f"region={b1[0]}:{b1[1]},{b2[0]}:{b2[1]}", "at=start"], "biases in data memory"),
    }


def wilson(k, n, z=1.96):
    if n == 0:
        return 0.0, 0.0
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return max(0.0, c - h), min(1.0, c + h)


def run_target(name, args, text_end, trials, workers, seed):
    per = [trials // workers + (1 if i < trials % workers else 0) for i in range(workers)]
    def job(i):
        cmd = [SIM, f"hex={HEX}", f"text_end={text_end}", f"trials={per[i]}", f"seed={seed * 1000 + i}"] + args
        return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    with ThreadPoolExecutor(workers) as ex:
        outs = list(ex.map(job, range(workers)))
    rows = []
    for o in outs:
        rows += list(csv.DictReader(io.StringIO(o)))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--trials", type=int, default=3000)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--targets", nargs="*")
    a = ap.parse_args()

    syms = symbols()
    t0, tlen = syms[".text"]
    text_end = t0 + tlen
    tg = targets(syms)
    names = a.targets or list(tg)
    os.makedirs(os.path.join(REPO, "fault/results"), exist_ok=True)

    print(f"{'target':10} {'trials':>7}  " + "  ".join(f"{o:>17}" for o in OUTCOMES))
    for name in names:
        args, desc = tg[name]
        rows = run_target(name, args, text_end, a.trials, a.workers, a.seed)
        path = os.path.join(REPO, f"fault/results/{name}.csv")
        with open(path, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader(); w.writerows(rows)
        n = len(rows)
        cells = []
        for o in OUTCOMES:
            k = sum(r["outcome"] == o for r in rows)
            lo, hi = wilson(k, n)
            cells.append(f"{100*k/n:5.1f}% [{100*lo:4.1f},{100*hi:4.1f}]")
        print(f"{name:10} {n:>7}  " + "  ".join(f"{c:>17}" for c in cells), flush=True)


if __name__ == "__main__":
    main()
