#!/usr/bin/env python3
"""
Correction-capability evaluation over the REAL heavy-ion upset database.

Replays the CERN 2018 / GSI 2019 readback-differencing records through a model
of each code configuration and reports, per configuration, what fraction of
real upset events is corrected / left uncorrected / actively MIS-corrected.

Configurations
  none      no scrubbing (baseline)
  ecc       per-frame Frame-ECC only (SEM-like single-bit correction)
  par2d     vertical interleaved parity only (no per-frame Hamming)
  both      the implemented mixed 2-D code
  both_hard identical for configuration upsets; differs only for upsets in the
            scrubber's own fabric, which is accounted separately

Model, per frame within one accumulation window
  Frame-ECC: 1 upset bit  -> corrected
             2 bits       -> detected, not locatable (word field XOR-cancels
                             for same-word pairs; even flag otherwise)
             >=3 odd      -> syndrome decodes to a WRONG position -> MIS-CORRECT
             >=4 even     -> detected, not corrected
  2-D parity: the subgroup's parity yields the frame's exact error pattern when
              that frame is the ONLY errored frame in its subgroup -> corrected
              at any multiplicity. Two errored frames in one subgroup are
              resolvable only when their syndromes coincide.

Grouping follows the implemented geometry: group = column, subgroup = minor mod S.
"""
import sys, pandas as pd
from collections import Counter

S = 2  # subgroups per group; overridden per configuration in main (2026-09-03)

COLS = "time_tag,time_tag2,readback_capture,is_angled,golden_bit_value,frame_address,frame_index,block_type,top_bot,row_address,column_address,minor_address,word_of_frame,bit_word,bit_frame,masked_bit,masked_frame,essential_bit,non_essential_frame,logic_block,specific_logic,specific_logic_2".split(',')

def load(path):
    d = pd.read_csv(path, low_memory=False)
    if 'block_type' not in d.columns:      # GSI export carries no header row
        d = pd.read_csv(path, low_memory=False, header=None, names=COLS)
    d = d[d.block_type == 'CLB'].copy()          # configuration frames we scrub
    for col in ('column_address','minor_address','word_of_frame','bit_word'):
        d[col] = pd.to_numeric(d[col], errors='coerce')
    d = d.dropna(subset=['column_address','minor_address','word_of_frame','bit_word'])
    d['subgroup'] = d.minor_address.astype(int) % S
    return d

def classify_frame(bits):
    """bits: list of (word,bit) in one frame. Returns ecc verdict."""
    n = len(bits)
    if n == 1:
        return 'corrected'
    if n % 2 == 1:      # odd multiplicity -> syndrome points somewhere WRONG
        return 'miscorrected'
    return 'uncorrected'   # even -> detected, not locatable by Hamming alone

def evaluate(d, window='capture'):
    """window='capture' uses the beam readback interval (pessimistic: it is far
    longer than one scrub sweep, so it over-states coincidence)."""
    res = {k: Counter() for k in ('none','ecc','par2d','both')}
    # a group key identifies one interleaved parity group in one window
    gkey = ['time_tag','top_bot','row_address','column_address']
    for _, g in d.groupby(gkey, sort=False):
        # frames in this group, and their bit lists
        frames = {}
        for (minor,), fg in g.groupby(['minor_address'], sort=False):
            frames[int(minor)] = list(zip(fg.word_of_frame.astype(int),
                                          fg.bit_word.astype(int)))
        # subgroup occupancy
        sub = {}
        for m, bits in frames.items():
            sub.setdefault(m % S, []).append((m, bits))
        for m, bits in frames.items():
            n = len(bits)
            res['none']['uncorrected'] += 1
            res['ecc'][classify_frame(bits)] += 1
            peers = sub[m % S]
            alone = len(peers) == 1
            # --- 2-D parity alone
            if alone:
                res['par2d']['corrected'] += 1
            else:
                # two frames, same subgroup: resolvable only if syndromes agree
                if len(peers) == 2 and all(len(b) == 1 for _, b in peers) \
                   and peers[0][1][0] == peers[1][1][0]:
                    res['par2d']['corrected'] += 1
                else:
                    res['par2d']['uncorrected'] += 1
            # --- both: Hamming fast path, parity for the rest.
            # 2026-09-03, from the silicon replay (FINDINGS 16.3): correction is
            # SEQUENTIAL. Single-bit peers in the subgroup are located by the
            # ECC and repaired first, after which a multi-bit frame is alone
            # for the parity. So the condition is not "alone" but "the only
            # multi-bit frame in its subgroup". 297/300 real events agree.
            if n == 1:
                res['both']['corrected'] += 1
            elif sum(1 for _, b in peers if len(b) >= 2) <= 1:
                res['both']['corrected'] += 1
            else:
                if len(peers) == 2 and all(len(b) == 1 for _, b in peers) \
                   and peers[0][1][0] == peers[1][1][0]:
                    res['both']['corrected'] += 1
                else:
                    res['both']['uncorrected'] += 1
    return res

def report(name, res, total_frames):
    print(f"\n=== {name} : {total_frames} upset-bearing frames ===")
    print(f"{'config':10} {'corrected':>10} {'uncorrected':>12} {'MIS-corrected':>14}   {'coverage':>9}")
    for k in ('none','ecc','par2d','both'):
        c = res[k]['corrected']; u = res[k]['uncorrected']; m = res[k]['miscorrected']
        print(f"{k:10} {c:10} {u:12} {m:14}   {100*c/total_frames:8.2f}%")

if __name__ == '__main__':
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--S', type=int, nargs='+', default=[2, 4, 8])
    ap.add_argument('--csv', action='store_true', help='one CSV line per (dataset, S, config)')
    a = ap.parse_args()
    data = {}
    for tag, path in (('CERN 2018','CERN2018/CERN2018_UPSETS.csv'),
                      ('GSI 2019','GSI2019/GSI2019_UPSETS.csv')):
        try:
            data[tag] = load(path)
        except FileNotFoundError:
            print("missing", path)
    if a.csv:
        print("dataset,S,config,corrected,uncorrected,miscorrected,coverage_pct")
    for tag, d in data.items():
        for s_ in a.S:
            S = s_
            res = evaluate(d)
            total = sum(res['none'].values())
            if a.csv:
                for k in ('none','ecc','par2d','both'):
                    c = res[k]['corrected']; u = res[k]['uncorrected']; m = res[k]['miscorrected']
                    print(f"{tag},{S},{k},{c},{u},{m},{100*c/total:.2f}")
            else:
                report(f"{tag}  S={S}", res, total)
