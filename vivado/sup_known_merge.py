#!/usr/bin/env python3
"""Merge every sup_known log of the night into one per-(build,bit) table (FINDINGS §19.2)."""
import os
SCRUBBER_ROOT = os.environ.get("SCRUBBER_ROOT", os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # repository root
import glob, os, re, statistics as st
from collections import defaultdict
D = os.path.join(SCRUBBER_ROOT, 'campaign/2026-09-04_night')
rows = defaultdict(list)
for f in sorted(glob.glob(f'{D}/*sup_known*.log')):
    name = os.path.basename(f)[:-4]
    build = 'prod' if 'prod' in name else 's4g64' if '_s4' in name else 'test'
    for line in open(f, errors='replace'):
        if not line.startswith('CSV,') or line.startswith('CSV,idx'):
            continue
        p = line.strip().split(',')
        try:
            k = next(i for i, x in enumerate(p) if x in ('alive', 'DEAD', 'BLIND'))
            far, w, b = p[k-3:k]; verdict, alarm, rec = p[k], int(p[k+1]), int(p[k+2])
        except (StopIteration, ValueError, IndexError):
            print('skip:', name, line.strip()[:80]); continue
        rows[(build, f'{far} w{w} b{b}')].append((verdict, alarm, rec, name))
order = ['prod', 's4g64', 'test']
print('| build | bit | trials | alive | DEAD | BLIND | alarm ms med / max | recovery ms med / max |')
print('|---|---|---|---|---|---|---|---|')
tot = 0; fail_rec = 0
for (build, bit), r in sorted(rows.items(), key=lambda kv: (order.index(kv[0][0]), kv[0][1])):
    n = len(r)
    if n < 10: continue
    tot += n
    v = [x[0] for x in r]
    bad = [x for x in r if x[0] != 'alive']
    fail_rec += sum(1 for x in bad if x[2] < 0)
    al = [x[1] for x in bad]; rc = [x[2] for x in bad if x[2] >= 0]
    alarm = f'{int(st.median(al))} / {max(al)}' if al else '—'
    recov = f'{int(st.median(rc))} / {max(rc)}' if rc else '—'
    print(f'| {build} | `{bit}` | {n} | {v.count("alive")} | {v.count("DEAD")} | {v.count("BLIND")} | {alarm} | {recov} |')
print(f'\n{tot} directed trials, {fail_rec} failed recoveries; logs: ' +
      ', '.join(sorted({x[3] for r in rows.values() for x in r})))
