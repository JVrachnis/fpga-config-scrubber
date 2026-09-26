#!/usr/bin/env python3
"""BRAM-content upset targets from the logic-location file.

.ll lines for block RAM:  Bit <off> 0x<frame> <bit> Block=RAMB18_XxYy Ram=B:BIT<n>
The frame is a block-type-1 (BRAM content) frame; the scrubber never scans
those, so a flipped bit stays flipped: a real, persistent SEU in the memory.
Sites are classified from the placement report (rams.log).
"""
import os
SCRUBBER_ROOT = os.environ.get("SCRUBBER_ROOT", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # repository root
import re, random, pathlib
LL = pathlib.Path("/tmp/selfupset/design.ll")
RAMS = pathlib.Path("/tmp/rams.log")
OUT = pathlib.Path(os.path.join(SCRUBBER_ROOT, "vivado/bram_targets.tcl.out"))
site_kind = {}
for line in RAMS.read_text().splitlines():
    m = re.match(r"RAM (\S+) (\S+) (\S+)", line)
    if not m: continue
    site, ref, cell = m.groups()
    if "golden_par_mem" in cell: kind = "golden"
    elif "calc_par_mem" in cell: kind = "calc"
    elif "syndr_handler" in cell: kind = "handler"
    elif "algorithm" in cell: kind = "algorithm"
    elif "injector" in cell: kind = "injector"
    else: kind = "other"
    site_kind[site] = kind
by_kind = {}
pat = re.compile(r"^Bit\s+\d+\s+0x([0-9A-Fa-f]+)\s+(\d+)\s+Block=(RAMB\S+)\s+Ram=B:(\S+)")
with LL.open() as fh:
    for line in fh:
        m = pat.match(line)
        if not m: continue
        far, bit, site, ram = int(m.group(1), 16), int(m.group(2)), m.group(3), m.group(4)
        kind = site_kind.get(site, "unplaced")
        if kind in ("injector", "unplaced"): continue
        if ram.startswith("PARBIT"): continue          # BRAM's own parity bits: unused
        by_kind.setdefault(kind, []).append((far, bit // 32, bit % 32, site))
random.seed(20260903)
with OUT.open("w") as f:
    f.write("# far word bit kind site\n")
    for kind, lst in by_kind.items():
        random.shuffle(lst)
        for far, w, b, site in lst[:400]:
            f.write(f"0x{far:06X} {w} {b} {kind} {site}\n")
for kind, lst in by_kind.items():
    fars = {x[0] for x in lst}
    print(f"{kind:10s} {len(lst):7d} bits in {len(fars)} frames, block type {sorted({(x[0]>>23)&7 for x in lst})}")
print("wrote", OUT)
