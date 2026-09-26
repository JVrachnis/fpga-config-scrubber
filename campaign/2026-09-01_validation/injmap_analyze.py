#!/usr/bin/env python3
"""Cross-check the measured injectable-frame set against the scan geometry.

Input : the CSV lines emitted by vivado/injmap2.tcl
Output: injectability by column and by minor, and the derived rule.

Scan geometry from rtl/v1.8/scrubber_ip_pkg.vhd:
    cols_per_row_c = 56, top_rows_c = 1, bot_rows_c = 1,
    max_frames_per_group_c = 64  (minors per column)
    masked_frames_c = {0x001C02, 0x01EB9A}
"""
import sys, re
import pandas as pd

COLS_PER_ROW = 56
MASKED = {0x001C02, 0x01EB9A}

rows = []
for line in open(sys.argv[1], errors="ignore"):
    m = re.match(r"CSV,(0x[0-9A-Fa-f]+),(\d+),(\d+),(\d+),(\d+)\s*$", line.strip())
    if m:
        rows.append(dict(far=int(m.group(1), 16), half=int(m.group(2)),
                         col=int(m.group(3)), minor=int(m.group(4)),
                         ok=int(m.group(5))))
df = pd.DataFrame(rows)
if df.empty:
    sys.exit("no CSV rows found")

print(f"grid points measured: {len(df)}   injectable: {df.ok.sum()} "
      f"({100*df.ok.mean():.1f}%)\n")

print("=== injectable by column (rows = column, cols = minor) ===")
piv = df.pivot_table(index=["half", "col"], columns="minor", values="ok")
print(piv.to_string(na_rep="-"))

print("\n=== by column, both halves pooled ===")
bycol = df.groupby("col").ok.agg(["sum", "count"])
bycol["rate"] = bycol["sum"] / bycol["count"]
print(bycol.to_string())

print("\n=== by minor, both halves pooled ===")
bymin = df.groupby("minor").ok.agg(["sum", "count"])
bymin["rate"] = bymin["sum"] / bymin["count"]
print(bymin.to_string())

print("\n=== by half ===")
print(df.groupby("half").ok.agg(["sum", "count", "mean"]).to_string())

# --- hypothesis tests -------------------------------------------------------
print("\n=== cross-check against the scan geometry ===")
inrange = df[df.col < COLS_PER_ROW]
outrange = df[df.col >= COLS_PER_ROW]
print(f"col <  {COLS_PER_ROW} (in scan range) : "
      f"{inrange.ok.sum()}/{len(inrange)} injectable")
print(f"col >= {COLS_PER_ROW} (out of range)  : "
      f"{outrange.ok.sum()}/{len(outrange)} injectable")

good_cols = sorted(df[df.ok == 1].col.unique())
bad_cols = sorted(c for c in df.col.unique() if c not in good_cols)
print(f"\ncolumns with at least one injectable frame: {good_cols}")
print(f"columns with none                        : {bad_cols}")

if good_cols:
    mods = {m: sorted({c % m for c in good_cols}) for m in (2, 4, 8, 16)}
    print("\ncolumn residues among injectable columns:")
    for m, v in mods.items():
        print(f"  mod {m:2d}: {v}")

hit_masked = df[df.far.isin(MASKED)]
if len(hit_masked):
    print(f"\nmasked frames present in the grid: "
          f"{[hex(f) for f in hit_masked.far]} -> ok={list(hit_masked.ok)}")

df.to_csv("injectable_map.csv", index=False)
print("\nwrote injectable_map.csv")
