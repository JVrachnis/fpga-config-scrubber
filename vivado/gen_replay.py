#!/usr/bin/env python3
"""Beam-data replay vectors: real CERN-2018 / GSI-2019 upset EVENTS as injection sets.

An event = all upset bits recorded in one (capture, half, row, column) group of
the readback-differencing database, i.e. exactly one parity group of the
implemented geometry. Each event's structure - which minors, which words,
which bits, how many frames - is kept; only the column is re-targeted onto a
measured-injectable column of the test device (the real data's columns include
unreachable ones), keeping minor mod S so the subgroup pattern is preserved.

Output: replay_events.tcl  ->  set EVENTS { {name {far word mask} {far word mask} ...} ... }
Selection: every multi-frame event (>=2 frames in the group), plus the 40
largest single-frame multi-bit events, plus 40 random single-bit events.
"""
import os
SCRUBBER_ROOT = os.environ.get("SCRUBBER_ROOT", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # repository root
BEAM_ROOT = os.environ.get("BEAM_ROOT", ".")  # directory holding temp/{CERN2018,GSI2019}/*_UPSETS.csv (beam data, not included)
import sys, random, re, pathlib
import pandas as pd
sys.path.insert(0, os.path.join(BEAM_ROOT, "temp"))
from coverage import load  # same loader/cleaning as the coverage model

random.seed(20260903)
S = int(sys.argv[1]) if len(sys.argv) > 1 else 2
def predict(frames):
    # coverage.py 'both' rule: single-bit frames by ECC; multi-bit frames need to be
    # alone in their subgroup (two single-bit frames with equal syndrome excepted)
    sub = {}
    for m, bits in frames.items(): sub.setdefault(m % S, []).append((m, bits))
    for m, bits in frames.items():
        if len(bits) == 1: continue
        peers = sub[m % S]
        if len(peers) == 1: continue
        return 0
    return 1
INJ_COLS_BOTH = list(range(18, 28)) + list(range(34, 43))       # both halves
INJ_COLS_TOP  = INJ_COLS_BOTH + list(range(43, 56))              # top half only
_pkg = pathlib.Path(os.path.join(SCRUBBER_ROOT, "rtl/v1.8/device_geometry_pkg.vhd")).read_text()
def _minors(name):
    body = re.search(name + r"\s*:\s*col_minors_arr_t\s*:=\s*\((.*?)\);", _pkg, re.S).group(1)
    return {int(a): int(b) for a, b in re.findall(r"(\d+)\s*=>\s*(\d+)", body)}
TOP, BOT = _minors("top_col_minors_c"), _minors("bot_col_minors_c")

def retarget(minors_needed, half):
    """pick an injectable column in this half whose frame count covers the minors used"""
    need = max(minors_needed) + 3
    cols = [c for c in (INJ_COLS_TOP if half == 0 else INJ_COLS_BOTH)
            if (TOP if half == 0 else BOT).get(c, 0) >= need]
    return random.choice(cols) if cols else None

events = []
for tag, path in (("CERN", os.path.join(BEAM_ROOT, "temp/CERN2018/CERN2018_UPSETS.csv")),
                  ("GSI",  os.path.join(BEAM_ROOT, "temp/GSI2019/GSI2019_UPSETS.csv"))):
    d = load(path)
    gkey = ["time_tag", "top_bot", "row_address", "column_address"]
    multi, single_multibit, single_bit = [], [], []
    for (tt, tb, row, col), g in d.groupby(gkey, sort=False):
        half = 0 if str(tb).strip().lower().startswith("t") else 1
        frames = {}
        for m, fg in g.groupby("minor_address", sort=False):
            frames[int(m)] = sorted(set(zip(fg.word_of_frame.astype(int), fg.bit_word.astype(int))))
        nbits = sum(len(v) for v in frames.values())
        ev = (tag, half, frames, nbits)
        if len(frames) >= 2: multi.append(ev)
        elif nbits >= 2:     single_multibit.append(ev)
        else:                single_bit.append(ev)
    single_multibit.sort(key=lambda e: -e[3])
    big  = [e for e in multi if len(e[2]) >= 4]
    f3   = [e for e in multi if len(e[2]) == 3]
    f2   = [e for e in multi if len(e[2]) == 2]
    events += big + random.sample(f3, min(60, len(f3))) + random.sample(f2, min(60, len(f2))) \
              + single_multibit[:10] + random.sample(single_bit, 10)

out = ["# Real beam events re-targeted onto injectable columns. gen_replay.py", "set EVENTS {"]
kept = 0; skipped = 0
for i, (tag, half, frames, nbits) in enumerate(events):
    col = retarget(frames.keys(), half)
    if col is None: skipped += 1; continue
    # keep minor mod S structure: the minor values themselves are preserved
    ups = []
    for m, bits in frames.items():
        words = {}
        for w, b in bits: words.setdefault(w, 0); words[w] |= (1 << b)
        for w, mask in words.items():
            far = (half << 22) | (col << 7) | m
            ups.append(f"{{0x{far:06X} {w} 0x{mask:08X}}}")
    name = f"{tag}_{i}_f{len(frames)}_b{nbits}_p{predict(frames)}"
    out.append(f"  {{{name} " + " ".join(ups) + "}")
    kept += 1
out.append("}")
pathlib.Path(os.path.join(SCRUBBER_ROOT, f"vivado/replay_events_S{S}.tcl")).write_text("\n".join(out) + "\n")
nmulti = sum(1 for e in events if len(e[2]) >= 2)
print(f"events: {len(events)} ({nmulti} multi-frame), written {kept}, skipped {skipped}")
