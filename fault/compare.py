#!/usr/bin/env python3
"""Compare the baseline and hardened fault-injection campaigns.

Reads fault/results/ (baseline), fault/results_hard/ (register parity +
int16 biases + model checksum) and fault/results_b16/ (int16 biases only),
writes fault/figures/hardening.png and fault/results_hard/summary.md.

    ~/.venvs/rv32i-ml/bin/python fault/campaign.py --variant hard
    ~/.venvs/rv32i-ml/bin/python fault/campaign.py --variant b16 --targets biases
    ~/.venvs/rv32i-ml/bin/python fault/compare.py
"""
import csv, glob, math, os
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIG = os.path.join(REPO, "fault/figures")
SERIES = ["#2a78d6", "#eb6834"]          # categorical slots 1-2 (validated)
SURFACE, INK, INK2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"
TARGET_DESC = {
    "regfile": "Register file (x1–x31)", "pc": "Program counter",
    "id_ex": "ID/EX pipeline reg", "ex_mem": "EX/MEM pipeline reg", "mem_wb": "MEM/WB pipeline reg",
    "instr": "Fetched instruction", "ldata": "Loaded data word",
    "code": "Code in instr. memory", "W1": "Layer-1 weights", "W2": "Layer-2 weights", "biases": "Biases",
}
OUTCOMES = ["masked", "tolerated", "sdc", "crash", "detected"]


def load(d):
    out = {}
    for p in sorted(glob.glob(os.path.join(REPO, d, "*.csv"))):
        out[os.path.basename(p)[:-4]] = list(csv.DictReader(open(p)))
    return out


def rate(rows, o):
    return sum(r["outcome"] == o for r in rows) / len(rows)


def wilson(k, n, z=1.96):
    p = k / n; d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return max(0, c - h), min(1, c + h)


def cell(rows, o):
    k = sum(r["outcome"] == o for r in rows); n = len(rows); lo, hi = wilson(k, n)
    return f"{100*k/n:.1f}% ({100*lo:.1f}–{100*hi:.1f})"


base, hard, b16 = load("fault/results"), load("fault/results_hard"), load("fault/results_b16")
order = [t for t in TARGET_DESC if t in base and t in hard]
order.sort(key=lambda t: rate(base[t], "sdc"), reverse=True)

# ------------------------------------------------------------ figure
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10})
fig, axes = plt.subplots(1, 2, figsize=(10, 5.4), facecolor=SURFACE, sharey=True)
ys = np.arange(len(order))[::-1]
h = 0.36
for ax, o, title in ((axes[0], "sdc", "Silent wrong answer"), (axes[1], "crash", "Crash / no output")):
    ax.set_facecolor(SURFACE)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    for s in ("left", "bottom"):
        ax.spines[s].set_color(GRID)
    ax.tick_params(colors=INK2, labelsize=9)
    ax.grid(axis="x", color=GRID, linewidth=0.8); ax.set_axisbelow(True)
    vmax = max(100 * rate(base[t], o) for t in order)
    for i, (src, name) in enumerate(((base, "baseline"), (hard, "hardened"))):
        vals = [100 * rate(src[t], o) for t in order]
        ax.barh(ys + (h / 2 if i == 0 else -h / 2), vals, height=h - 0.04, color=SERIES[i],
                edgecolor=SURFACE, linewidth=1, label=name)
        for y, v in zip(ys, vals):
            ax.text(v + vmax * 0.015, y + (h / 2 if i == 0 else -h / 2), f"{v:.1f}", va="center",
                    fontsize=7.5, color=INK2)
    ax.set_xlim(0, vmax * 1.15)
    ax.set_title(title, loc="left", color=INK, fontsize=11)
    ax.set_xlabel("share of single-bit flips (%)", color=INK2)
axes[0].set_yticks(ys, [TARGET_DESC[t] for t in order], color=INK)
axes[0].legend(frameon=False, loc="lower right", fontsize=9, labelcolor=INK)
fig.suptitle("Effect of hardening, 3 000 flips per structure", x=0.01, ha="left", color=INK, fontsize=12)
fig.tight_layout(); fig.savefig(os.path.join(FIG, "hardening.png"), dpi=160); plt.close(fig)

# ------------------------------------------------------------ summary
def total(src, o):
    rows = [r for t in order for r in src[t]]
    return 100 * rate(rows, o), len(rows)

lines = ["# Hardened build: fault-injection results", "",
         "Register parity (fail-stop), int16 biases, model checksum checked before",
         "inference. Same structures, trial counts and seeds as the baseline.", "",
         "| Structure | Masked | Tolerated | Silent wrong answer (SDC) | Crash / no output | Detected |",
         "|---|---|---|---|---|---|"]
for t in order:
    lines.append(f"| {TARGET_DESC[t]} | " + " | ".join(cell(hard[t], o) for o in OUTCOMES) + " |")
lines += ["", "## Baseline vs hardened (silent wrong answers / crashes)", "",
          "| Structure | SDC baseline | SDC hardened | Crash baseline | Crash hardened | Detected |",
          "|---|---|---|---|---|---|"]
for t in order:
    lines.append(f"| {TARGET_DESC[t]} | {100*rate(base[t],'sdc'):.1f}% | {100*rate(hard[t],'sdc'):.1f}% | "
                 f"{100*rate(base[t],'crash'):.1f}% | {100*rate(hard[t],'crash'):.1f}% | "
                 f"{100*rate(hard[t],'detected'):.1f}% |")
(sb, n), (sh, _) = total(base, "sdc"), total(hard, "sdc")
(cb, _), (ch, _) = total(base, "crash"), total(hard, "crash")
lines.append(f"| **All {n} trials** | **{sb:.1f}%** | **{sh:.1f}%** | **{cb:.1f}%** | **{ch:.1f}%** | "
             f"**{total(hard, 'detected')[0]:.1f}%** |")
if "biases" in b16:
    lines += ["", "## int16 biases alone (no checksum, no parity)", "",
              "| Biases | SDC | Tolerated | Masked |", "|---|---|---|---|",
              f"| int32 (baseline) | {cell(base['biases'],'sdc')} | {cell(base['biases'],'tolerated')} | {cell(base['biases'],'masked')} |",
              f"| int16 | {cell(b16['biases'],'sdc')} | {cell(b16['biases'],'tolerated')} | {cell(b16['biases'],'masked')} |"]
lines.append("")
open(os.path.join(REPO, "fault/results_hard/summary.md"), "w").write("\n".join(lines))
print("\n".join(lines))
print("wrote fault/figures/hardening.png and fault/results_hard/summary.md")
