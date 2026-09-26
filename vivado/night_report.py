#!/usr/bin/env python3
"""Summarize campaign/2026-09-04_night/*.log."""
import os
SCRUBBER_ROOT = os.environ.get("SCRUBBER_ROOT", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # repository root
import re, pathlib, statistics as st
D = pathlib.Path(os.path.join(SCRUBBER_ROOT, "campaign/2026-09-04_night"))
def rows(name, prefix="CSV,"):
    f = D / name
    if not f.exists(): return []
    return [l.strip().split(",") for l in f.read_text(errors="ignore").splitlines() if l.startswith(prefix) and not l.startswith("CSV,idx") and not l.startswith("CSV,name") and not l.startswith("CSV,minute")]
def last(name, pat):
    f = D / name
    if not f.exists(): return "(missing)"
    m = [l for l in f.read_text(errors="ignore").splitlines() if pat in l]
    return m[-1] if m else "(none)"
print("== 01 guard ==");        print(last("01_guard.log", "valid"))
for tag in ("02_campaign_v2", "03_campaign_v2", "08_campaign_S4"):
    r = rows(tag + ".log")
    if not r: print(f"== {tag}: no rows"); continue
    n = len(r); det = sum(int(x[5]) for x in r); ex = sum(int(x[13]) for x in r); ok = sum(int(x[15]) for x in r)
    cor = [int(x[8]) for x in r if int(x[5]) and int(x[8]) > 0]
    print(f"== {tag}: n={n} detected={det} exact_restore={ex} PASS={ok}  hw correction latency us: median {st.median(cor) if cor else '-'} max {max(cor) if cor else '-'}")
    for x in r:
        if not int(x[15]): print("   FAIL", x[2], x[3], x[4], "det", x[5], "rehits", x[9], "exact", x[13], "rej", x[14])
print("== 04 w091b =="); print("\n".join(l for l in (D/"04_w091b.log").read_text(errors="ignore").splitlines() if l.startswith("0x")) if (D/"04_w091b.log").exists() else "(missing)")
print("== 05 supervised ==");   print(last("05_supervised.log", "SUPERVISED"))
r = rows("05_supervised.log")
if r:
    from collections import Counter
    print("   verdicts:", dict(Counter(x[5] for x in r)))
    al = [int(x[6]) for x in r if x[5] != "alive"]; rc = [int(x[7]) for x in r if x[5] != "alive" and int(x[7]) > 0]
    if al: print(f"   alarm ms: median {st.median(al)} max {max(al)};  recovery ms: median {st.median(rc) if rc else '-'}")
for tag in ("06_replay_S2", "07_replay_S4"):
    print(f"== {tag} =="); print("  ", last(tag + ".log", "REPLAY"))
    r = rows(tag + ".log")
    if r:
        obs = lambda x: 1 if (int(x[6]) == 0 and float(x[7]) < 50 and int(x[8]) == 0) else 0
        print(f"   events={len(r)} corrected={sum(obs(x) for x in r)} pred_uncorrectable={sum(1 for x in r if x[4]=='0')} disagreements={sum(1 for x in r if obs(x)!=int(x[4]))}")
        print("   failures:", [x[1] for x in r if not obs(x)][:8])
print("== 09 soak ==");         print("  ", last("09_soak.log", "SOAK")); print("  ", last("09_soak.log", "CANARY"))
print("== 10 cern0 ILA ==");    print("  ", last("10_hunt.log", "iter")); print("  ", last("10_hunt.log", "CAPTURED"))
