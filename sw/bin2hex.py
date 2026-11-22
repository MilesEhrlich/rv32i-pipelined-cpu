#!/usr/bin/env python3
"""Convert a flat little-endian binary into $readmemh files:
     OUT          one 32-bit word per line (instruction memory)
     OUT.lane0-3  one byte per line for each byte lane (data memory, see dmem.v)
"""
import sys
data = open(sys.argv[1], "rb").read()
data += b"\0" * (-len(data) % 4)
out = sys.argv[2]
with open(out, "w") as f:
    for i in range(0, len(data), 4):
        f.write("%08x\n" % int.from_bytes(data[i:i+4], "little"))
for k in range(4):
    with open("%s.lane%d" % (out, k), "w") as f:
        for i in range(k, len(data), 4):
            f.write("%02x\n" % data[i])
