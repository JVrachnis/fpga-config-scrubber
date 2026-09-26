#!/usr/bin/env python3
"""Summarize campaign/2026-09-03_matrix/<config>/ into one table (markdown)."""
import os
SCRUBBER_ROOT = os.environ.get("SCRUBBER_ROOT", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # repository root
import re, sys, pathlib, statistics as st
import pandas as pd

ROOT = pathlib.Path(os.path.join(SCRUBBER_ROOT, "campaign/2026-09-03_matrix"))
cov = pd.read_csv(ROOT / "coverage_by_S.csv") if (ROOT / "coverage_by_S.csv").exists() else None

def util(d):
    t = (d / "util.rpt").read_text(errors="ignore") if (d / "util.rpt").exists() else ""
    def g(label):
        m = re.search(r"\|\s*" + re.escape(label) + r"\s*\|\s*(\d+)", t); return int(m.group(1)) if m else None
    return g("Slice LUTs"), g("Slice Registers"), g("Block RAM Tile")

def wns(d):
    f = d / "wns.txt"
    if f.exists():
        m = re.search(r"WNS\s+(-?[\d.]+)", f.read_text()); 
        if m: return float(m.group(1))
    t = (d / "timing.rpt").read_text(errors="ignore") if (d / "timing.rpt").exists() else ""
    m = re.search(r"WNS\(ns\).*?\n.*?\n\s*(-?[\d.]+)", t, re.S); return float(m.group(1)) if m else None

def period(d):
    f = d / "period.log"
    if not f.exists(): return None
    ts = [int(m.group(1)) for m in re.finditer(r"^(\d+)\s+0x[0-9A-F]+\s+<- A", f.read_text(errors="ignore"), re.M)]
    if len(ts) < 3: return None
    iv = [b - a for a, b in zip(ts, ts[1:])]
    return f"{st.median(iv):.0f} ms (JTAG-bound)" if st.median(iv) < 25 else f"{st.median(iv):.0f} ms"

def campaign(d):
    f = d / "campaign.log"
    if not f.exists(): return None
    rows = [l.split(",") for l in f.read_text(errors="ignore").splitlines() if l.startswith("CSV,") and not l.startswith("CSV,idx")]
    if not rows: return None
    n = len(rows); det = sum(int(r[5]) for r in rows); ok = sum(int(r[11]) for r in rows)
    lat = [int(r[6]) for r in rows if int(r[5])]
    return dict(n=n, det=det, pass_=ok, med=st.median(lat) if lat else None, mx=max(lat) if lat else None,
                fails=[(r[2], "nodet" if not int(r[5]) else f"rehits={r[7]} drops={r[9]} wd={r[10]}") for r in rows if not int(r[11])])

def conc(d):
    f = d / "conc.log"
    if not f.exists(): return None
    out = {}
    for l in f.read_text(errors="ignore").splitlines():
        if l.startswith("CSV,S="):
            _, s, name, n, dirty, busy, alg, wd = l.split(",")
            out[name] = (int(n), int(dirty), float(busy), int(wd))
    return out

print("| config | LUT | FF | BRAM | WNS ns | pass period | campaign det/corr/PASS of n | latency med/max ms | capacity: k adj2 in one column (dirty of k) | 2 adj2 same subgroup | coverage CERN/GSI |")
print("|---|---|---|---|---|---|---|---|---|---|---|")
for d in sorted(p for p in ROOT.iterdir() if p.is_dir() and not p.name.startswith("_")):
    S = int(re.search(r"S(\d+)", d.name).group(1))
    L, F, B = util(d); W = wns(d); P = period(d); C = campaign(d); K = conc(d)
    cap = ""
    if K:
        ks = sorted((int(re.search(r"x(\d+)_", k).group(1)), v[1], v[2]) for k, v in K.items() if "distinct" in k)
        cap = ", ".join(f"k={k}:{dirty}{'*' if busy > 50 else ''}" for k, dirty, busy in ks)
        same = K.get("adj2_x2_col44_same_subgroup"); same = f"{same[1]}/2 dirty{'*' if same[2] > 50 else ''}" if same else ""
    else: same = ""
    cv = ""
    if cov is not None:
        c = cov[(cov.S == S) & (cov.config == "both")]
        if len(c): cv = " / ".join(f"{r.coverage_pct:.2f}%" for _, r in c.iterrows())
    camp = f"{C['det']}/{C['pass_']}/{C['pass_']} of {C['n']}" if C else ""
    lat = f"{C['med']:.0f} / {C['mx']}" if C and C["med"] is not None else ""
    print(f"| {d.name} | {L} | {F} | {B} | {W} | {P or ''} | {camp} | {lat} | {cap} | {same} | {cv} |")
    if C and C["fails"]:
        print(f"|  | | | | | | fails: {'; '.join(f'{a} {b}' for a,b in C['fails'])} | | | | |")
print("\n* = handler busy > 50% during the 5 s watch (livelock)")
