# Hardened build: fault-injection results

Register parity (fail-stop), int16 biases, model checksum checked before
inference. Same structures, trial counts and seeds as the baseline.

| Structure | Masked | Tolerated | Silent wrong answer (SDC) | Crash / no output | Detected |
|---|---|---|---|---|---|
| Biases | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 100.0% (99.9–100.0) |
| Code in instr. memory | 57.6% (55.8–59.3) | 9.5% (8.5–10.6) | 7.6% (6.7–8.6) | 7.9% (7.0–8.9) | 17.5% (16.2–18.9) |
| MEM/WB pipeline reg | 63.6% (61.8–65.3) | 24.1% (22.6–25.7) | 5.4% (4.6–6.3) | 3.1% (2.5–3.8) | 3.8% (3.2–4.6) |
| Register file (x1–x31) | 53.8% (52.0–55.5) | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 46.2% (44.5–48.0) |
| Fetched instruction | 57.6% (55.8–59.3) | 31.1% (29.4–32.7) | 2.3% (1.8–2.9) | 5.0% (4.3–5.9) | 4.1% (3.4–4.8) |
| EX/MEM pipeline reg | 80.3% (78.8–81.7) | 13.3% (12.2–14.6) | 2.7% (2.2–3.3) | 2.0% (1.5–2.5) | 1.7% (1.3–2.2) |
| ID/EX pipeline reg | 80.6% (79.1–82.0) | 10.5% (9.5–11.6) | 1.1% (0.8–1.5) | 5.9% (5.1–6.8) | 1.9% (1.4–2.4) |
| Program counter | 24.1% (22.6–25.7) | 7.2% (6.3–8.2) | 0.8% (0.5–1.2) | 66.6% (64.9–68.3) | 1.3% (0.9–1.7) |
| Layer-2 weights | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 100.0% (99.9–100.0) |
| Loaded data word | 97.9% (97.4–98.4) | 1.1% (0.8–1.5) | 0.0% (0.0–0.2) | 0.0% (0.0–0.1) | 1.0% (0.7–1.4) |
| Layer-1 weights | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 100.0% (99.9–100.0) |

## Baseline vs hardened (silent wrong answers / crashes)

| Structure | SDC baseline | SDC hardened | Crash baseline | Crash hardened | Detected |
|---|---|---|---|---|---|
| Biases | 15.7% | 0.0% | 0.0% | 0.0% | 100.0% |
| Code in instr. memory | 10.6% | 7.6% | 10.8% | 7.9% | 17.5% |
| MEM/WB pipeline reg | 5.9% | 5.4% | 3.7% | 3.1% | 3.8% |
| Register file (x1–x31) | 3.7% | 0.0% | 16.0% | 0.0% | 46.2% |
| Fetched instruction | 2.7% | 2.3% | 4.8% | 5.0% | 4.1% |
| EX/MEM pipeline reg | 2.3% | 2.7% | 1.7% | 2.0% | 1.7% |
| ID/EX pipeline reg | 1.5% | 1.1% | 4.7% | 5.9% | 1.9% |
| Program counter | 1.0% | 0.8% | 67.0% | 66.6% | 1.3% |
| Layer-2 weights | 0.1% | 0.0% | 0.0% | 0.0% | 100.0% |
| Loaded data word | 0.0% | 0.0% | 0.0% | 0.0% | 1.0% |
| Layer-1 weights | 0.0% | 0.0% | 0.0% | 0.0% | 100.0% |
| **All 33000 trials** | **4.0%** | **1.8%** | **9.9%** | **8.2%** | **34.3%** |

## int16 biases alone (no checksum, no parity)

| Biases | SDC | Tolerated | Masked |
|---|---|---|---|
| int32 (baseline) | 15.7% (14.4–17.0) | 67.1% (65.4–68.7) | 17.3% (16.0–18.7) |
| int16 | 2.9% (2.4–3.6) | 63.3% (61.6–65.0) | 33.8% (32.1–35.5) |
