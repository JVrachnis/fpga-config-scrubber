# `vivado/` — build, instrumentation and silicon-campaign scripts

75 Tcl scripts accumulated across the 2026 revival. Most are one-shot probes kept as
evidence of how a result was obtained; this index marks the ones that are still the
**current** way to do something. Everything runs headless.

```
VIVADO=$XILINX/2025.2/Vivado/bin      # adjust if relocated
$VIVADO/vivado -mode batch -source <script>.tcl              # build / netlist scripts
$VIVADO/xsdb   <script>.tcl                                  # board scripts
```

## Current flow — use these

| Script | Purpose |
|---|---|
| `rebuild_force.tcl` | **The** build. Resets the module-reference OOC run (otherwise RTL edits are silently cached), re-synthesizes, implements, writes the bitstream. |
| `rebuild_addpkg.tcl` / `rebuild_addpchk.tcl` | Same, but first `add_files` a newly created source. Needed once per new RTL file — a new file is *not* picked up automatically. |
| `synth_only.tcl` | Synthesis only. Use before an `insert_ila*` run (which needs a current `synth_1` netlist). |
| `export_bd.tcl` | Re-exports the block design to `../scrubber_injection_bd.tcl`. Run after any BD change — the generated BD sources are tool output, not authored input. |
| `ila_prog_only.tcl` | Program the FPGA + `ps7_init` + devcfg, **without** starting the scrubber (so an ILA can be armed first). |
| `final_campaign2.tcl` | 30 s background census + 12-injection campaign with first-detection latency. *Superseded by `campaign_honest.tcl`.* |
| `lib.tcl` | **Source this in every board script.** DAP recovery, hand-off-asserting `freeze`, CTRL-preserving capture ack (a bare-0x1 ack silently drops HOLD), recovery-word readers. |
| `campaign_honest.tcl` | **The** acceptance campaign. Verdict requires detected AND corrected AND no golden re-init AND no watchdog fire. Replaces `big_campaign.tcl`, whose "150/150" run detected 2. Expect 147/150 on `campaign_vectors_reachable.tcl`. |
| `thaw_char.tcl` / `period3.tcl` | Post-thaw recovery and direct scan-period measurement. |
| `matrix.sh` / `matrix_report.py` | Configuration matrix: build, program, run the suite per (S,G,WD); table in `campaign/2026-09-03_matrix/MATRIX.md`. |
| `selfupset_ebd.py` / `selfupset.tcl` | Self-upset: essential bits of the scrubber's own frames (from `.ebd` aligned via `.ll`), one per trial, with blindness check and auto-reprogram. |
| `gen_replay.py` / `replay.tcl` | Beam-event replay with per-event model prediction. `replay.tcl S maxEvents [start]`. |
| `lib.tcl readframe` | Frame readback (Rev. 1.14): mask-0 injection + buffer read; `framediff`. Use it to VERIFY every injection claim. Only valid FARs (per-column minor table): an invalid minor corrupts neighbouring frames. |
| `notseen_rb.tcl` | Readback-instrumented self-upset re-test. |

| `campaign_conc.tcl` | Concurrency-capacity campaign (FINDINGS section 14): N independent, same-column, same-subgroup, even-multiplicity sets. Expect everything corrected except two even-multiplicity frames in one subgroup. |
| `multi.tcl` | Plant N upsets with one hand-off each (thaw into HOLD between them). Verified to N=8. |
| `injmap2.tcl` / `injmap3.tcl` | Map which FAR columns are actually injectable. `injmap3` also runs no-injection controls, which is how column 56 was shown to be a false positive. |
| `gen_vectors.py` | Emits `campaign_vectors_reachable.tcl` -- vectors restricted to injectable frames. **Use this vector file, not `campaign_vectors.tcl`** (only 61% of the old file is reachable). |
| `midproof.tcl` | Freeze proof + mid-correction injection (FINDINGS section 11). |
| `midreach.tcl` | Paired frozen/plain acceptance on the reachable vectors. Expect ~29/30 both arms. |
| `firstep.tcl` | First-injection regression: the deterministic reproducer for the watchdog/golden defect. Expect 5/5 `ok`. |
| `stress.tcl` | 28 injections, two per frame across 14 frames spanning both device halves. Expect `ok=28 stuck=0`. |

## Acceptance criteria (final build)

```
firstep.tcl          5/5 ok
stress.tcl           ok=28 stuck=0
final_campaign2.tcl  12/12 corrected, no recurrences
```

Note on `final_campaign2.tcl` output: per-injection lines can read `RECURRING!` as an
artifact — the script demands 900 ms of quiet inside a fixed 2.5 s window, which is
impossible when first detection lands after ~1.9 s. The summary line and a separate
live-scan recheck are authoritative.

## Instrumentation (ILA)

`insert_ila*.tcl` differ only in their probe set; each opens the current `synth_1`
netlist, creates a debug core, then implements. Run `synth_only.tcl` first, and strip
stale debug constraints from the wrapper XDC before a **non**-ILA build or
implementation fails with `Chipscope 16-213 unconnected channels`.

| Script | Probe set | What it established |
|---|---|---|
| `insert_ila.tcl` | correction chain (19 probes) | original correction bring-up |
| `insert_ila2/3.tcl` | Frame-ECC chain, qualified | FAR/pulse phase; frame attribution identity |
| `insert_ila4.tcl` | handler + controller + algorithm | correction-episode autopsy |
| `insert_ila5/6.tcl` | ICAP data streams; merge internals | the parity-merge phase race |
| `insert_ila7/8.tcl` | parity-calculator write port | pass coverage, poison/perr state |
| `insert_ila9.tcl` | merge read port + classification | **merge correct, calc reads all-zero** |
| `insert_ila10.tcl` | calc write **and** read ports | **pass ends with calc identically zero** → golden contained the error |

Capture scripts live in `/tmp` by convention during a session; the evidence CSVs they
produced are archived under `campaign/2026-08-29_branch_hardening/`.

## Recovery

| Symptom | Fix |
|---|---|
| `no targets found with "ARM*#0"` (DAP wedged) | `targets -set 1; rst -system` — see `rst.tcl` pattern in the campaign notes |
| JTAG unresponsive after many sessions | `pkill -x hw_server`, then reprogram; board state is unaffected |
| RTL edits have no effect on silicon | you skipped `rebuild_force.tcl` — the OOC run was cached |
| `Chipscope 16-213 unconnected channels` | stale ILA constraints in `scrubber_injection_wrapper.xdc`; strip `create_debug*` / `connect_debug*` / `u_ila_0` / `dbg_hub` lines |

## Historical probes

The remaining scripts (`diag*`, `census*`, `farmap*`, `collast*`, `wordsweep`,
`sync_test`, `twod_silicon`, `latency_campaign`, `silicon_validation`, …) are the
one-shot experiments behind specific documented results — the measured column map, the
column-last coverage hole, the 36/40 µs correction latency, the syndrome XOR-accounting
that rehabilitated the injector. Kept deliberately: each is the reproduction recipe for
a claim made in the thesis or TRM.

> The `cern0*.tcl` reproducers for the four-frame same-column case (FINDINGS §16.4) are not
> published: they replay an upset pattern taken from the CERN beam data, whose terms of use are
> not established. The finding itself is described in `campaign/2026-09-01_validation/FINDINGS.md`.
