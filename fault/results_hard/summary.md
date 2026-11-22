# Hardened build: fault-injection results

Register parity (fail-stop), int16 biases, model checksum checked before
inference. Same structures, trial counts and seeds as the baseline.

| Structure | Masked | Tolerated | Silent wrong answer (SDC) | Crash / no output | Detected |
|---|---|---|---|---|---|
| Biases | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 100.0% (99.9–100.0) |
| Code in instr. memory | 56.6% (54.8–58.4) | 10.0% (8.9–11.1) | 7.6% (6.7–8.6) | 8.0% (7.1–9.1) | 17.8% (16.5–19.2) |
| Register file (x1–x31) | 53.8% (52.0–55.5) | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 46.2% (44.5–48.0) |
| MEM/WB pipeline reg | 63.3% (61.6–65.0) | 24.4% (22.9–25.9) | 5.4% (4.6–6.3) | 3.1% (2.5–3.8) | 3.8% (3.2–4.6) |
| Fetched instruction | 58.1% (56.3–59.8) | 30.8% (29.1–32.4) | 2.3% (1.8–2.9) | 4.8% (4.1–5.7) | 4.1% (3.4–4.8) |
| EX/MEM pipeline reg | 79.3% (77.8–80.7) | 14.4% (13.2–15.7) | 2.7% (2.2–3.3) | 2.0% (1.5–2.5) | 1.7% (1.3–2.2) |
| ID/EX pipeline reg | 79.7% (78.2–81.1) | 11.5% (10.4–12.7) | 1.1% (0.8–1.6) | 5.8% (5.0–6.7) | 1.9% (1.4–2.4) |
| Program counter | 25.2% (23.6–26.8) | 7.2% (6.3–8.1) | 0.8% (0.5–1.2) | 65.6% (63.9–67.3) | 1.3% (0.9–1.7) |
| Layer-2 weights | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 100.0% (99.9–100.0) |
| Loaded data word | 97.9% (97.4–98.4) | 1.1% (0.8–1.5) | 0.0% (0.0–0.2) | 0.0% (0.0–0.1) | 1.0% (0.7–1.4) |
| Layer-1 weights | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 0.0% (0.0–0.1) | 100.0% (99.9–100.0) |

## Baseline vs hardened (silent wrong answers / crashes)

| Structure | SDC baseline | SDC hardened | Crash baseline | Crash hardened | Detected |
|---|---|---|---|---|---|
| Biases | 15.7% | 0.0% | 0.0% | 0.0% | 100.0% |
| Code in instr. memory | 10.9% | 7.6% | 11.0% | 8.0% | 17.8% |
| Register file (x1–x31) | 6.6% | 0.0% | 15.8% | 0.0% | 46.2% |
| MEM/WB pipeline reg | 5.9% | 5.4% | 3.7% | 3.1% | 3.8% |
| Fetched instruction | 2.6% | 2.3% | 4.5% | 4.8% | 4.1% |
| EX/MEM pipeline reg | 2.4% | 2.7% | 1.7% | 2.0% | 1.7% |
| ID/EX pipeline reg | 1.5% | 1.1% | 4.5% | 5.8% | 1.9% |
| Program counter | 0.9% | 0.8% | 66.3% | 65.6% | 1.3% |
| Layer-2 weights | 0.1% | 0.0% | 0.0% | 0.0% | 100.0% |
| Loaded data word | 0.0% | 0.0% | 0.0% | 0.0% | 1.0% |
| Layer-1 weights | 0.0% | 0.0% | 0.0% | 0.0% | 100.0% |
| **All 33000 trials** | **4.2%** | **1.8%** | **9.8%** | **8.1%** | **34.3%** |

## int16 biases alone (no checksum, no parity)

| Biases | SDC | Tolerated | Masked |
|---|---|---|---|
| int32 (baseline) | 15.7% (14.4–17.0) | 67.1% (65.4–68.7) | 17.3% (16.0–18.7) |
| int16 | 2.9% (2.4–3.6) | 63.3% (61.6–65.0) | 33.8% (32.1–35.5) |
