#!/usr/bin/env python3
"""Analyze the fault-injection campaign and the weight-bit sweep.

1. Summarize fault/results/<target>.csv (outcome rates, 95% Wilson CIs).
2. Cross-check: every weight/bias flip trial run on the simulated CPU is
   recomputed with the bit-exact integer model (ml/model.npz); outcomes must
   agree exactly.
3. Exhaustive sweep: flip every bit of every weight and bias, one at a time,
   and measure the accuracy on all 540 test images (fast: one flip changes a
   single hidden unit or output, so it is updated incrementally).
4. Figures in fault/figures/, tables in fault/results/summary.md.

    ~/.venvs/rv32i-ml/bin/python fault/analyze.py
"""
import csv, glob, math, os, subprocess
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(REPO, "fault/results")
FIG = os.path.join(REPO, "fault/figures")
os.makedirs(FIG, exist_ok=True)
OUTCOMES = ["masked", "tolerated", "sdc", "crash"]
LABEL = {"masked": "masked", "tolerated": "tolerated (scores changed)",
         "sdc": "silent wrong answer", "crash": "crash / no output"}
# ordinal blue ramp, light = harmless -> dark = worst (validated, --ordinal)
OUT_COLOR = {"masked": "#86b6ef", "tolerated": "#3987e5", "sdc": "#1c5cab", "crash": "#0d366b"}
SERIES = ["#2a78d6", "#eb6834"]          # categorical slots 1-2 (validated)
SURFACE, INK, INK2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"

TARGET_DESC = {
    "regfile": "Register file (x1–x31)", "pc": "Program counter",
    "id_ex": "ID/EX pipeline reg", "ex_mem": "EX/MEM pipeline reg", "mem_wb": "MEM/WB pipeline reg",
    "instr": "Fetched instruction", "ldata": "Loaded data word",
    "code": "Code in instr. memory", "W1": "Layer-1 weights", "W2": "Layer-2 weights", "biases": "Biases",
}
ABI = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1"] + [f"a{i}" for i in range(8)] + \
      [f"s{i}" for i in range(2, 12)] + ["t3", "t4", "t5", "t6"]


def wilson(k, n, z=1.96):
    p = k / n; d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return max(0, c - h), min(1, c + h)


def style(ax):
    ax.set_facecolor(SURFACE)
    for s in ["top", "right"]:
        ax.spines[s].set_visible(False)
    for s in ["left", "bottom"]:
        ax.spines[s].set_color(GRID)
    ax.tick_params(colors=INK2, labelsize=9)
    ax.grid(axis="x", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)


# ------------------------------------------------------------ load data
d = np.load(os.path.join(REPO, "ml/model.npz"))
W1, b1, W2, b2, SHIFT1 = d["W1"], d["b1"], d["W2"], d["b2"], int(d["SHIFT1"])
Xte, yte, Xe = d["Xte"], d["yte"], d["Xe"]

results = {}
for path in sorted(glob.glob(os.path.join(RES, "*.csv"))):
    results[os.path.basename(path)[:-4]] = list(csv.DictReader(open(path)))

# ------------------------------------------------------- 1. summary
def bad_rate(t):           # share of flips ending in SDC or crash
    r = results[t]
    return sum(x["outcome"] in ("sdc", "crash") for x in r) / len(r)

order = sorted((t for t in TARGET_DESC if t in results), key=bad_rate, reverse=True)

lines = ["| Structure | Trials | Masked | Tolerated | Silent wrong answer (SDC) | Crash / no output |",
         "|---|---|---|---|---|---|"]
for t in order:
    r = results[t]; n = len(r)
    cells = []
    for o in OUTCOMES:
        k = sum(x["outcome"] == o for x in r); lo, hi = wilson(k, n)
        cells.append(f"{100*k/n:.1f}% ({100*lo:.1f}–{100*hi:.1f})")
    lines.append(f"| {TARGET_DESC[t]} | {n} | " + " | ".join(cells) + " |")
summary_md = "\n".join(lines)

# --------------------------------------------- 2. cross-check memory flips
def symbols():
    out = subprocess.run(["/opt/homebrew/opt/llvm/bin/llvm-nm", "-S", os.path.join(REPO, "sw/build/digits.elf")],
                         capture_output=True, text=True, check=True).stdout
    s = {}
    for line in out.splitlines():
        p = line.split()
        if len(p) == 4: s[p[3]] = (int(p[0], 16), int(p[1], 16))
    return s

def infer(x, W1_, b1_, W2_, b2_):
    h = np.clip((x @ W1_ + b1_) >> SHIFT1, 0, 127)
    out = h @ W2_ + b2_
    return out, out.argmax(axis=1)

def flip_int8(v, bit):
    u = (int(v) & 0xFF) ^ (1 << bit)
    return u - 256 if u >= 128 else u

def flip_int32(v, bit):
    u = (int(v) & 0xFFFFFFFF) ^ (1 << bit)
    return u - (1 << 32) if u >= (1 << 31) else u

base_out_e, base_pred_e = infer(Xe, W1, b1, W2, b2)
syms = symbols()
check_total = check_agree = 0
for t in ("W1", "W2", "biases"):
    for r in results.get(t, []):
        addr = int(r["site"].split("@")[1], 16); bit = int(r["bit"]); n = int(r["image"])
        A1, B1, A2, B2 = W1.copy(), b1.copy(), W2.copy(), b2.copy()
        if t == "W1":
            i = addr - syms["W1"][0]; A1.flat[i] = flip_int8(A1.flat[i], bit)
        elif t == "W2":
            i = addr - syms["W2"][0]; A2.flat[i] = flip_int8(A2.flat[i], bit)
        else:
            for name, arr in (("b1", B1), ("b2", B2)):     # map the address by explicit range
                start, size = syms[name]
                if start <= addr < start + size:
                    off = addr - start
                    arr[off // 4] = flip_int32(arr[off // 4], 8 * (off % 4) + bit)
                    break
            else:
                raise ValueError(f"bias trial address {addr:#x} is outside b1 and b2")
        out, pred = infer(Xe[n:n+1], A1, B1, A2, B2)
        if pred[0] != base_pred_e[n]: exp = "sdc"
        elif not np.array_equal(out[0], base_out_e[n]): exp = "tolerated"
        else: exp = "masked"
        check_total += 1; check_agree += (exp == r["outcome"])

# ------------------------------------------- 3. exhaustive weight sweep
acc1 = Xte @ W1 + b1                       # (540, 32)
h0 = np.clip(acc1 >> SHIFT1, 0, 127)
out0 = h0 @ W2 + b2
pred0 = out0.argmax(axis=1)
acc_base = (pred0 == yte).mean()
N = len(yte)

def eval_out(out):
    pred = out.argmax(axis=1)
    return (pred != pred0).mean(), (pred == yte).mean()

sweep = {"W1": [], "W2": [], "b1": [], "b2": []}   # (bit, changed_frac, accuracy)
# All arithmetic is int32 and wraps on overflow, exactly like the CPU's 32-bit
# adds (the CPU-vs-model cross-check above includes bias flips), so numpy's
# overflow warnings are expected here.
np.seterr(over="ignore")
for i in range(64):
    for j in range(32):
        for bit in range(8):
            dlt = flip_int8(W1[i, j], bit) - W1[i, j]
            hj = np.clip((acc1[:, j] + Xte[:, i] * dlt) >> SHIFT1, 0, 127)
            out = out0 + np.outer(hj - h0[:, j], W2[j])
            sweep["W1"].append((bit, *eval_out(out)))
for j in range(32):
    for k in range(10):
        for bit in range(8):
            dlt = flip_int8(W2[j, k], bit) - W2[j, k]
            out = out0.copy(); out[:, k] += h0[:, j] * dlt
            sweep["W2"].append((bit, *eval_out(out)))
for j in range(32):
    for bit in range(32):
        dlt = flip_int32(b1[j], bit) - b1[j]
        hj = np.clip((acc1[:, j] + dlt) >> SHIFT1, 0, 127)
        out = out0 + np.outer(hj - h0[:, j], W2[j])
        sweep["b1"].append((bit, *eval_out(out)))
for k in range(10):
    for bit in range(32):
        dlt = flip_int32(b2[k], bit) - b2[k]
        out = out0.copy(); out[:, k] += dlt
        sweep["b2"].append((bit, *eval_out(out)))
sw = {k: np.array(v) for k, v in sweep.items()}

# biases: how much harm sits in the upper 16 bits (values fit in ~11 bits)
b_all = np.vstack([sw["b1"], sw["b2"]]); b_drop = 100 * (acc_base - b_all[:, 2])
b_harm = int((b_drop >= 1).sum()); b_harm_hi = int(((b_drop >= 1) & (b_all[:, 0] >= 16)).sum())
b_maxabs = int(max(np.abs(b1).max(), np.abs(b2).max()))

def bit_table(arr, nbits):
    rows = []
    for b in range(nbits):
        s = arr[arr[:, 0] == b]
        drop = 100 * (acc_base - s[:, 2])
        rows.append((b, drop.mean(), drop.max(), (drop >= 1).mean() * 100))
    return rows

w_rows = {k: bit_table(sw[k], 8) for k in ("W1", "W2")}
b_rows = {k: bit_table(sw[k], 32) for k in ("b1", "b2")}

# -------------------------------------------------------- 4. figures
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10})

# Fig 1: outcome by structure (horizontal 100% stacked bars)
fig, ax = plt.subplots(figsize=(9, 5.2), facecolor=SURFACE); style(ax)
ys = np.arange(len(order))[::-1]
for y, t in zip(ys, order):
    r = results[t]; n = len(r); left = 0
    for o in OUTCOMES:
        w = 100 * sum(x["outcome"] == o for x in r) / n
        ax.barh(y, w, left=left, height=0.62, color=OUT_COLOR[o], edgecolor=SURFACE, linewidth=1.5,
                label=LABEL[o] if y == ys[0] else None)
        left += w
    bad = 100 * sum(x["outcome"] in ("sdc", "crash") for x in r) / n
    ax.text(101, y, f"{bad:.1f}%", va="center", fontsize=9, color=INK)
ax.set_yticks(ys, [TARGET_DESC[t] for t in order], color=INK)
ax.set_xlim(0, 100); ax.set_xlabel("share of single-bit flips (%)", color=INK2)
ax.text(101, ys[0] + 0.75, "SDC +\ncrash", fontsize=8, color=INK2, va="bottom")
ax.set_title("Outcome of one bit flip, by where it lands", loc="left", color=INK, fontsize=12, pad=28)
ax.legend(ncol=4, frameon=False, loc="lower left", bbox_to_anchor=(0, 1.0), fontsize=8.5, labelcolor=INK)
fig.tight_layout(); fig.savefig(os.path.join(FIG, "outcomes_by_structure.png"), dpi=160); plt.close(fig)

# Fig 2: weight bit position -> share of flips that cost >= 1 accuracy point
fig, ax = plt.subplots(figsize=(7.5, 4), facecolor=SURFACE); style(ax); ax.grid(axis="y", color=GRID); ax.grid(axis="x", visible=False)
xs = np.arange(8); wdt = 0.36
for s, (k, lab) in enumerate([("W1", "layer-1 weights (2048)"), ("W2", "layer-2 weights (320)")]):
    v = [r[3] for r in w_rows[k]]
    ax.bar(xs + (s - 0.5) * (wdt + 0.04), v, width=wdt, color=SERIES[s], label=lab)
ax.set_xticks(xs, [f"{b}" + ("\n(sign)" if b == 7 else "") for b in xs], color=INK2)
ax.set_xlabel("bit position in the int8 weight", color=INK2)
ax.set_ylabel("flips costing ≥1 accuracy point (%)", color=INK2)
ax.set_title("Only the top bits of a weight matter", loc="left", color=INK, fontsize=12)
w1_max = max(r[3] for r in w_rows["W1"])
ax.annotate(f"layer-1 weights: at most {w1_max:.1f}% at any bit", xy=(7 - 0.5 * (wdt + 0.04), w1_max),
            xytext=(4.2, 12), fontsize=8.5, color=INK2, arrowprops=dict(arrowstyle="-", color=INK2, lw=0.8))
ax.legend(frameon=False, fontsize=9, labelcolor=INK, loc="upper left")
fig.tight_layout(); fig.savefig(os.path.join(FIG, "weight_bit_sensitivity.png"), dpi=160); plt.close(fig)

# Fig 3: register file, per register
reg = results.get("regfile", [])
if reg:
    stats = []
    for i in range(1, 32):
        rr = [x for x in reg if x["site"] == f"x{i}"]
        if not rr: continue
        n = len(rr)
        stats.append((i, n, 100 * sum(x["outcome"] == "sdc" for x in rr) / n,
                      100 * sum(x["outcome"] == "crash" for x in rr) / n))
    stats.sort(key=lambda s: -(s[2] + s[3]))
    fig, ax = plt.subplots(figsize=(10, 4), facecolor=SURFACE); style(ax); ax.grid(axis="y", color=GRID); ax.grid(axis="x", visible=False)
    xs = np.arange(len(stats))
    sdc = [s[2] for s in stats]; cr = [s[3] for s in stats]
    ax.bar(xs, sdc, color=OUT_COLOR["sdc"], width=0.7, label=LABEL["sdc"], edgecolor=SURFACE, linewidth=1)
    ax.bar(xs, cr, bottom=sdc, color=OUT_COLOR["crash"], width=0.7, label=LABEL["crash"], edgecolor=SURFACE, linewidth=1)
    ax.set_xticks(xs, [f"x{s[0]}\n{ABI[s[0]]}" for s in stats], fontsize=7.5, color=INK2)
    ax.set_ylabel("flips causing SDC or crash (%)", color=INK2)
    ax.set_title(f"Register file: which registers matter (~{stats[0][1]} flips each)", loc="left", color=INK, fontsize=12)
    ax.legend(frameon=False, fontsize=9, labelcolor=INK)
    fig.tight_layout(); fig.savefig(os.path.join(FIG, "regfile_by_register.png"), dpi=160); plt.close(fig)

# --------------------------------------------------------- 5. report
def md_bits(rows, label):
    out = [f"| Bit | Mean accuracy drop (pts) | Worst drop (pts) | Flips costing ≥1 pt |", "|---|---|---|---|"]
    for b, mean, mx, frac in rows:
        out.append(f"| {b}{' (sign)' if (label=='int8' and b==7) or (label=='int32' and b==31) else ''} | {mean:.3f} | {mx:.1f} | {frac:.1f}% |")
    return "\n".join(out)

all_w = np.vstack([sw["W1"], sw["W2"]])
report = f"""# Fault-injection results (generated by fault/analyze.py)

## Outcome by structure

Single-bit flips while the CPU classifies one test image. Registers, PC,
pipeline registers and the fetched/loaded words are flipped at a uniformly
random cycle during the run; memory (code, weights, biases) is flipped before
the run starts. 95% Wilson confidence intervals in parentheses.

{summary_md}

## Cross-check: simulated CPU vs. integer model

{check_agree} of {check_total} weight/bias flip trials on the simulated CPU
produced exactly the outcome predicted by the bit-exact Python model.

## Exhaustive weight sweep ({len(sw['W1']) + len(sw['W2'])} weight bits, {len(sw['b1']) + len(sw['b2'])} bias bits)

Fault-free accuracy on all {N} test images: {100*acc_base:.2f}%.
Weight flips that change at least one of the {N} predictions: {100*(all_w[:,1] > 0).mean():.1f}%.

### Layer-1 weights (int8)
{md_bits(w_rows['W1'], 'int8')}

### Layer-2 weights (int8)
{md_bits(w_rows['W2'], 'int8')}

### Biases (int32)

{b_harm} of {len(b_all)} bias bit flips cost at least one accuracy point;
{b_harm_hi} of those ({100*b_harm_hi/b_harm:.0f}%) are in bits 16–31, which carry no
information (the largest bias magnitude is {b_maxabs}, which fits in 11 bits).

### Worst single bias flips
| Bias | Bit | Accuracy after flip |
|---|---|---|
""" + "\n".join(
    f"| {k}[{idx // 32 if k=='b1' else idx // 32}] | {int(sw[k][idx,0])} | {100*sw[k][idx,2]:.1f}% |"
    for k in ("b1", "b2") for idx in np.argsort(sw[k][:, 2])[:3]) + "\n"
open(os.path.join(RES, "summary.md"), "w").write(report)

print(report)
print(f"figures in {FIG}")
