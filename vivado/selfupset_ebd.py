#!/usr/bin/env python3
"""Self-upset targets from the essential-bits mask.

The logic-location file (.ll) maps flip-flop capture bits to (bitstream offset,
frame address, bit-in-frame). A configuration write does not alter those bits'
effect on running logic, so they are useless as targets - but they give the
bitstream offset of every frame that holds a scrubber flip-flop, and frames of
one column are consecutive in the bitstream (3232 bits each). The essential-bits
file (.ebd) is a mask over the same offsets: a 1 means the design's function
depends on that configuration bit.

Targets = essential bits in every frame of the columns that hold scrubber
flip-flops, restricted to injectable columns (FINDINGS 12). Bits of other logic
sharing those columns are included and cannot be told apart; the scrubber is
~90 % of the fabric so most are its own.
"""
import os
SCRUBBER_ROOT = os.environ.get("SCRUBBER_ROOT", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # repository root
import re, random, pathlib, sys
from collections import defaultdict
LL  = pathlib.Path("/tmp/selfupset/design.ll")
EBD = pathlib.Path("/tmp/selfupset/design.ebd")
OUT = pathlib.Path(os.path.join(SCRUBBER_ROOT, "vivado/selfupset_targets.tcl.out"))
FRAME_BITS = 101 * 32
INJ = set(range(18, 28)) | set(range(34, 43))          # both halves
INJ_TOP = INJ | set(range(43, 56))
_pkg = pathlib.Path(os.path.join(SCRUBBER_ROOT, "rtl/v1.8/device_geometry_pkg.vhd")).read_text()
def minors(name):
    body = re.search(name + r"\s*:\s*col_minors_arr_t\s*:=\s*\((.*?)\);", _pkg, re.S).group(1)
    return {int(a): int(b) for a, b in re.findall(r"(\d+)\s*=>\s*(\d+)", body)}
TOP, BOT = minors("top_col_minors_c"), minors("bot_col_minors_c")

# 1. .ll: frame base offsets, and which frames hold scrubber FFs
base = {}                     # far -> bitstream bit offset of the frame start
scrub_cols = set()            # (half, col)
pat = re.compile(r"^Bit\s+(\d+)\s+0x([0-9A-Fa-f]+)\s+(\d+)\s+.*Net=(\S+)")
with LL.open() as fh:
    for line in fh:
        m = pat.match(line)
        if not m: continue
        off, far, bit, net = int(m.group(1)), int(m.group(2), 16), int(m.group(3)), m.group(4)
        base.setdefault(far, off - bit)
        if "scrubber_wrapper_0/inst/scrubber/" in net:
            scrub_cols.add(((far >> 22) & 1, (far >> 7) & 0x3FF))
print(f"frames with FF bits in .ll: {len(base)}; scrubber columns (half,col): {sorted(scrub_cols)}")

# column base: use the lowest-minor frame known in the column
colbase = {}
for far, off in base.items():
    key = ((far >> 22) & 1, (far >> 7) & 0x3FF); minor = far & 0x7F
    if key not in colbase or minor < colbase[key][0]:
        colbase[key] = (minor, off)

# 2. .ebd: mask words in bitstream order (one 32-bit binary word per line after header)
words = []
with EBD.open() as fh:
    for line in fh:
        line = line.strip()
        if len(line) == 32 and set(line) <= {"0", "1"}: words.append(line)
print(f"ebd words: {len(words)}  ({len(words)*32} bits)")
def essential_bits(off0):
    """(word, bit) pairs with mask=1 for the frame starting at bit offset off0"""
    w0 = off0 // 32
    out = []
    for w in range(101):
        s = words[w0 + w] if w0 + w < len(words) else "0" * 32
        for b in range(32):
            # ebd line is MSB-first
            if s[31 - b] == "1": out.append((w, b))
    return out

# 3. targets
targets = []; controls = []
for (half, col) in sorted(scrub_cols):
    ok_cols = INJ_TOP if half == 0 else INJ
    if col not in ok_cols or (half, col) not in colbase: continue
    nmin = (TOP if half == 0 else BOT).get(col, 0)
    m0, off0 = colbase[(half, col)]
    for minor in range(nmin):
        far = (half << 22) | (col << 7) | minor
        off = off0 + (minor - m0) * FRAME_BITS
        if off < 0: continue
        ess = set(essential_bits(off))
        for w, b in ess:
            if w == 50: continue                     # ECC/clock word of the frame
            targets.append((far, w, b, "ebd1"))
        # control arm: non-essential bits of the same frame
        for w in range(0, 101, 7):
            for b in (3, 17, 29):
                if w != 50 and (w, b) not in ess: controls.append((far, w, b, "ebd0"))
print(f"essential bits in scrubber columns (injectable): {len(targets)}")
random.seed(20260903); random.shuffle(targets); random.shuffle(controls)
# interleave 3 essential : 1 control
mix = []
ci = iter(controls)
for i, t in enumerate(targets):
    mix.append(t)
    if i % 3 == 2:
        try: mix.append(next(ci))
        except StopIteration: pass
with OUT.open("w") as f:
    f.write(f"# far word bit module net   ({len(targets)} essential + {len(controls)} control bits, scrubber columns)\n")
    for far, w, b, kind in mix:
        f.write(f"0x{far:06X} {w} {b} {kind} -\n")
print("wrote", OUT)
