#!/usr/bin/env python3
"""Collect fault-injection trials from the Tang Nano (rtl/fi_top.v) and check
them against RTL simulation, trial by trial.

    NOLOAD=1 fault/build_board.sh base             # build the bitstream
    ~/.venvs/rv32i-ml/bin/python fault/board_fi.py base --trials 10000 --load

--load opens the serial port first, then loads build/fi_<variant>.fs, so the
port is read from the first report on (a USB-serial bridge left sending with
nobody reading it stalled once and needed a replug).

For every trial the board reports the image, the flipped bit, the cycle it
flipped at, and the raw results (class, checksum, exit, detection flags).
This script
  1. checks every fault-free (golden) run on the board against the Python
     model: class and logit checksum must match for that image,
  2. classifies each trial exactly like fi_sim.cpp,
  3. replays every trial in the Verilator simulation (same image, bit and
     cycle) and compares the outcomes one by one,
  4. writes fault/results_board/<variant>.csv and prints a summary.
"""
import argparse, collections, csv, glob, math, os, struct, subprocess, sys, termios, time
import numpy as np

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "fault/results_board")
PKT = struct.Struct("<2sHBBBBIIBIBBBIIIB")         # 37 bytes, see rtl/fi_top.v
assert PKT.size == 37
TARGET = {0: "regfile", 1: "pc", 2: "parity"}
VARIANT = {  # simulator, program, extra fi_sim args
    "base": ("build/fault/fi_sim", "digits", []),
    "hard": ("build/fault_hard/fi_sim", "digits_hard", ["parity=1"]),
}
OUTCOMES = ["masked", "tolerated", "sdc", "crash", "detected"]
FLIP_OFFSET = 1     # board flips at the edge ending cycle c = fi_sim flip after c+1 steps


def open_serial(port, baud=115200):
    fd = os.open(port, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
    attr = termios.tcgetattr(fd)
    attr[0] = 0                                     # iflag: raw
    attr[1] = 0                                     # oflag
    attr[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attr[3] = 0                                     # lflag: no echo, non-canonical
    speed = getattr(termios, f"B{baud}")
    attr[4] = attr[5] = speed
    termios.tcsetattr(fd, termios.TCSANOW, attr)
    termios.tcflush(fd, termios.TCIFLUSH)
    return fd


def read_trials(port, n, timeout_s, load=None):
    fd = open_serial(port)
    if load:
        r = subprocess.run(["openFPGALoader", "-b", "tangnano9k", load], capture_output=True, text=True)
        if "CRC check: Success" not in r.stdout + r.stderr:
            sys.exit("openFPGALoader failed:\n" + r.stdout[-500:] + r.stderr[-500:])
        # anything received so far came from the previous bitstream
        termios.tcflush(fd, termios.TCIFLUSH)
    buf, rows, last = b"", [], time.time()
    read_trials.dropped = 0
    pending = None          # until two reports with consecutive trial numbers
                            # arrive, data may be stale or a chance checksum match
    while len(rows) < n:
        try:
            chunk = os.read(fd, 4096)
        except BlockingIOError:
            chunk = b""
        if chunk:
            buf += chunk; last = time.time()
        elif time.time() - last > timeout_s:
            sys.exit(f"no data from {port} for {timeout_s}s (is the bitstream loaded?)")
        else:
            time.sleep(0.01)
        while True:
            i = buf.find(b"\xa5\x5a")
            if i < 0 or len(buf) - i < PKT.size:
                buf = buf[i:] if i >= 0 else buf[-1:]
                break
            f = PKT.unpack_from(buf, i)
            if sum(buf[i:i + PKT.size - 1]) & 0xFF != f[-1]:   # corrupted or not a header
                read_trials.dropped += 1
                buf = buf[i + 1:]; continue
            buf = buf[i + PKT.size:]
            if load and not rows and f[1] > 1000:     # a new load starts counting at 0
                continue
            row = dict(zip(["sync", "trial", "tgt", "reg", "bit", "image", "fire", "g_cycles",
                            "g_class", "g_check", "g_flags", "flags", "exit", "result",
                            "check", "cycles", "sum"], f))
            if not rows:
                if pending is None or row["trial"] != (pending["trial"] + 1) & 0xFFFF:
                    pending = row; continue
                rows.append(pending)
            rows.append(row)
            if len(rows) % 250 == 0:
                print(f"  {len(rows)} trials", flush=True)
    os.close(fd)
    return rows[:n]


def classify(r):        # same rules as fi_sim.cpp
    fl = r["flags"]
    if fl & 0x18: return "detected"                  # MMIO_FAULT or parity error
    if fl & 0x20 or not fl & 1 or r["exit"] or not fl & 2 or not fl & 4: return "crash"
    if r["result"] != r["g_class"]: return "sdc"
    if r["check"] != r["g_check"]: return "tolerated"
    return "masked"


def site(r):
    return {0: f"x{r['reg']}", 1: "pc_D", 2: f"p{r['reg']}"}[r["tgt"]]


def wilson(k, n, z=1.96):
    if n == 0: return 0, 0
    p = k / n; d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return max(0, c - h), min(1, c + h)


def text_end(prog):
    hdr = subprocess.run(["/opt/homebrew/opt/llvm/bin/llvm-objdump", "-h", f"sw/build/{prog}.elf"],
                         capture_output=True, text=True, check=True, cwd=REPO).stdout
    for line in hdr.splitlines():
        p = line.split()
        if len(p) >= 4 and p[1] == ".text":
            return int(p[3], 16) + int(p[2], 16)


def replay(rows, variant, offset):
    sim, prog, extra = VARIANT[variant]
    path = os.path.join(OUT, f"{variant}_replay_in.csv")
    with open(path, "w") as f:
        for r in rows:
            when = 0xFFFFFFFF if r["fire"] == 0xFFFFFFFF else r["fire"] + offset
            f.write(f"{site(r)},{r['bit']},{r['image']},{when}\n")
    out = subprocess.run([os.path.join(REPO, sim), f"hex=sw/build/{prog}.hex",
                          f"text_end={text_end(prog)}", f"replay={path}"] + extra,
                         capture_output=True, text=True, check=True, cwd=REPO).stdout
    os.remove(path)
    return list(csv.DictReader(out.splitlines()))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("variant", choices=list(VARIANT))
    ap.add_argument("--trials", type=int, default=3000)
    ap.add_argument("--port", default=None)
    ap.add_argument("--timeout", type=float, default=10)
    ap.add_argument("--load", action="store_true", help="load build/fi_<variant>.fs after opening the port")
    a = ap.parse_args()
    port = a.port or sorted(glob.glob("/dev/cu.usbserial-*"))[-1]   # 2nd FTDI channel = UART
    os.makedirs(OUT, exist_ok=True)

    print(f"reading {a.trials} trials from {port} ...")
    t0 = time.time()
    rows = read_trials(port, a.trials, a.timeout,
                       os.path.join(REPO, f"build/fi_{a.variant}.fs") if a.load else None)
    print(f"  done in {time.time() - t0:.0f} s; dropped {read_trials.dropped} reports that failed "
          f"their checksum (UART errors or false sync)")

    # 1. golden runs on the board vs the Python model
    m = np.load(os.path.join(REPO, "ml/model.npz"))
    bad_gold = [r for r in rows if r["g_flags"] & 7 != 7 or r["g_class"] != int(m["prede"][r["image"]])
                or r["g_check"] != int(m["sume"][r["image"]])]
    print(f"golden runs matching the Python model: {len(rows) - len(bad_gold)}/{len(rows)}")

    # 2-3. classify, replay in simulation, compare
    sim_rows = replay(rows, a.variant, FLIP_OFFSET)
    agree = 0; mism = []
    for r, s in zip(rows, sim_rows):
        r["outcome"] = classify(r); r["site"] = site(r); r["sim_outcome"] = s["outcome"]
        r["sim_golden_cycles"] = int(s["golden_cycles"])
        same = r["outcome"] == s["outcome"] and (r["outcome"] in ("crash", "detected") or
               (r["result"] == int(s["result"]) and f"{r['check']:08x}" == s["check"]))
        agree += same
        if not same: mism.append((r, s))
    gc = sum(r["g_cycles"] == r["sim_golden_cycles"] for r in rows)
    print(f"golden cycle counts equal to simulation: {gc}/{len(rows)}")
    print(f"trials whose outcome (and class/checksum) match the simulation replay: {agree}/{len(rows)}")
    for r, s in mism[:10]:
        print(f"  mismatch: {r['site']} bit {r['bit']} img {r['image']} fire {r['fire']}: "
              f"board {r['outcome']} (flags {r['flags']:02x}, {r['cycles']} cyc) vs sim {s['outcome']} ({s['cycles_run']} cyc)")

    # 4. save + summary
    keys = ["trial", "site", "bit", "image", "fire", "outcome", "sim_outcome", "cycles", "g_cycles",
            "sim_golden_cycles", "g_class", "g_check", "result", "check", "flags", "exit"]
    with open(os.path.join(OUT, f"{a.variant}.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys, extrasaction="ignore"); w.writeheader(); w.writerows(rows)
    by = collections.defaultdict(list)
    for r in rows:
        by["regfile" if r["tgt"] in (0, 2) else "pc"].append(r["outcome"])
    print(f"\n{'target':8} {'n':>5}  " + "  ".join(f"{o:>17}" for o in OUTCOMES))
    for t, outs in by.items():
        n = len(outs); cells = []
        for o in OUTCOMES:
            k = outs.count(o); lo, hi = wilson(k, n)
            cells.append(f"{100*k/n:5.1f}% [{100*lo:4.1f},{100*hi:4.1f}]")
        print(f"{t:8} {n:>5}  " + "  ".join(f"{c:>17}" for c in cells))
    print(f"wrote {os.path.relpath(os.path.join(OUT, a.variant + '.csv'), REPO)}")


if __name__ == "__main__":
    main()
