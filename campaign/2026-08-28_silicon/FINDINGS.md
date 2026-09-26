# Silicon validation of r64b0554 — 2026-08-28

Bitstream: rebuilt from fixed RTL (scan-driver advance/wrap fixes, live diag),
WNS +2.11 ns. Board: Zybo Z7-10 via xsdb. Scripts in vivado/: silicon_validation,
freeze_probe, hypothesis_test, twod_silicon, handshake_probe, starvation_test,
counter_probe, sbu_path_test.

## Confirmed good (matches sim)
- Golden-parity init completes (<15 ms sweep; +75 ms incl. startup).
- Continuous full-range scanning: ~3.6k+ frames/s observed via 8-bit frame counter
  (undercount; true rate higher — counter aliases at JTAG sampling rate).
- Live diag map works: healthy 0x41 exactly as sim predicted.
- Scan-driver fixes: no stuck passes, group sequencing sane.
- CTRL bit0 low pauses the scan (by design) — NOTE: every historical
  "corrected" recheck used cc ending CTRL=0x0, i.e. THE SCAN WAS FROZEN DURING
  ALL PRIOR CORRECTION VERIFICATION. Those rechecks were blind.

## Finding 1 — injector REHABILITATED (ECC-unaware theory refuted)
Injections at pristine frames (0x0A00 etc.) produce syndromes that track the
commanded word/bit exactly: w10,b3 -> syn 0x1483 = odd|enc(10)<<5|3. Sequential
injections into one frame accumulate: observed syndromes are the exact XOR of
all injected enc(w,b) terms (0x3C3^0x488=0x74B; ^0x653=0x1118; ^0x9BF=0x8A7).
The injector plants exact parameter-addressed single- AND multi-bit patterns.
A plain flip leaves the embedded frame ECC stale — which is what a real SEU
does. No ECC-aware rework is needed for SEU emulation.
- Addressing quirk: error lands at commanded FAR + 2 minors (0x0A00 -> 0x0A02).
- Injection at non-minor-0 FAR (0x0A02) did not land (canonical addressing
  required, as suspected in 2021 notes).
- The historical fixed syndrome 0x0653 belongs to BACKGROUND frames (see 2).
  The old canonical target 0x2000 is one of them. All "invariant syndrome"
  evidence is explained by targeting a background frame; zero-mask "errors"
  were the background frame's pre-existing inconsistency detected by the
  injector's own RMW read.

## Finding 2 — background ECC-inconsistent frames (masking gap)
Fresh boot, no injection, live scan: recurring captures with syn=0x0653
(= enc(w24,b19)) at 0x001C02 (persistent), 0x0001EB9A, 0x00EB06, 0x011496
(transient). Likely dynamic frames (LUTRAM/SRL of the design itself) whose
runtime content breaks the bitstream-computed embedded ECC — the classic
masked-frames problem. The identical syndrome across frames is unexplained
(w24b19 signature) — candidate lead for the write-path investigation.

## Finding 3 — CORRECTION DOES NOT LAND ON SILICON (new, previously masked)
A single injected bit persists >60 s (thousands of scan passes) with syndrome
bit-identical (0x1483) throughout. Meanwhile the new event counters show
start_error_correction and error_correction_done pulsing constantly and in
lockstep, and EDC ICAP write cycles completing (busy-fall toggle). So the
handler detects, commands corrections, the EDC executes write cycles — and
the frame content never changes. In the closed-loop sim the identical RTL
corrects in ~100 us.
Leading hypotheses:
  (a) parity-reconstruction write = buffer ^ calc with calc reading ~0 on
      silicon -> rewrites the same broken content (syndrome unchanged);
  (b) write lands at a wrong FAR on real geometry (transient 0x653 frames at
      odd FARs may be clobbered victims);
  (c) both.
Discrimination attempt via the SBU path (two errors, same subgroup) failed
because the injector needs canonical (minor-0) FARs.

## Next step
ILA insertion (mark_debug nets already in RTL) on the EDC/controller:
capture one correction cycle — path taken, calc_word_rd_data values, FAR and
data of the FDRI write. One capture answers (a)/(b) definitively.
Then: masked-frames list for the background frames (Make_Masked_frames.py flow).

## Session 2 (2026-08-29 night): ILA-driven correction-chain diagnosis

### Fixed and closed-loop-verified in sim (commit 02b7361)
- TB fecc model made silicon-faithful (FAR steps AFTER the pulse) -> TB
  reproduced the silicon correction failure exactly; then:
- syndrome_handler: entry index bookkeeping (stale first-entry address,
  off-by-one next-slot, missing minor-0 group-first store)  [ILA-proven]
- syndrome_handler: entries used delayed_far (frame N-1); now delayed_far2,
  with same-cycle subgroup (v_subgroup) for flag bookkeeping
- algorithm_icap_if: busy-edge-gated icap_start deadlocked vs auto-resynced
  controller; now level-start while granted (pcalc pattern)
- Closed-loop TB: ALL CHECKS PASSED with the faithful timing model.

### Still failing on silicon; root causes localized by the fecc-chain ILA
1. SCAN OVERRUN FLOOD (the real "background frames" mechanism): each scan
   pass overruns its group/column boundary - after col 55 the burst streams
   30+ garbage frames from the invalid col-56+ region, EVERY one flagging
   syn=0x0653; the handler stores an entry per frame (captured: entries for
   frames 1..31 of "group 0x1C00" in one sweep). This floods the syndromes
   memory every sweep, drowns real errors, and explains the 0x653 ubiquity,
   the historical "fixed syndrome", and probably the wedges.
   -> pcalc parity_calc group-change exit does not fire for 30+ frames on
   silicon. Measured: SYNDROMEVALID arrives at controller word_index=63 (not
   100); the exit condition requires word_index=100 AND next_far_group_change.
   Investigate the flag/word_index phase relationship with the captured data.
2. calc parity read = all zeros during CORRECT_WITH_PARITY on silicon ->
   reconstruction rewrites the erroneous frame unchanged. Subgroup attribution
   (locked_subgroup) vs err-frame LSB likely off by one frame; needs the
   accumulation-vs-entry alignment fixed AFTER the overrun flood is stopped.
3. Capture FAR (CAP_FAR) shows error frame +1 (injector "lands at +2 minors"
   was actually +1 frame with a +1 capture offset). Entry efa=1 for cap_far
   0x0A02 is probably CORRECT (real error in 0x0A01).

### Measured silicon facts (ila_fecc_chain_capture.csv)
- SYNDROMEVALID pulses every 101 cycles at controller word_index=63.
- At the pulse for readback position P: fecc_far = P+1 region boundary behavior
  visible across the col-55 -> col-56 crossing (0x1B80 -> 0x1C01 -> 0x1C02...).
- handler delayed_far = fecc_far two pulses back (per-pulse chain).
- pcalc calc writes alternate subgroup addr 0/1 per frame as designed.

### Next session plan (priority order)
1. Fix scan overrun (pcalc group-change exit on real timing) - kills the 0x653
   flood, un-swamps the syndrome memory. Extend core_tb with a multi-column
   FAR model (invalid region after group end) to reproduce first.
2. Re-check injected-frame correction on silicon (may already work once the
   flood is gone and entries align).
3. calc subgroup attribution alignment (if still needed).
4. Then: 2-D double-bit on silicon, masked-frames list, doc revision
   (injector rehabilitation + real background mechanism).

## RESOLUTION (2026-08-29, commit 1deaf5e): CORRECTION VERIFIED ON SILICON

ILA-calibrated frame identity ((1-cycle-delayed fecc_far)-1) + sticky
group-change flag. Closed-loop TB: ALL PASS. Silicon campaign (12 injections,
live-scan verification, 120 ms polls):
- 8/12 observed: detected exactly once, then absent = DETECTED+CORRECTED.
  Includes ADJACENT DOUBLE-BIT (2-D) corrections on silicon (bits 4-5, w20;
  and more), bit 31, word 60, word 3.
- 4/12 never captured: corrected before the first poll (sweep ~10-20 ms).
- Zero recurrences. Zero false positives from static frames.
- Background reduced from a 30+-frame flood per sweep to one genuinely
  inconsistent frame (0x001C02, syn 0x0653) -> masked-frames candidate.
- The injector needs canonical (minor-0) FARs; capture FAR displays frame+2.

First live-scan-verified autonomous correction in the project's history.
The 2-D adjacent-double-bit correction is demonstrated on hardware.

## Hardening session (2026-08-29 day, commit ed2aab6+)

1. MASKED-FRAMES + GEOMETRY VALIDITY FILTER (scrubber_ip): Frame-ECC events
   filtered before the handler for (a) an explicit masked-FAR generic list
   (future LUTRAM designs) and (b) any address outside block-0 space
   (block/=0, row/=0, col>55). 3-min census had shown ALL background 0x0653
   events decode to invalid addresses - no genuinely dynamic frames exist.
   Handler also got an empty-fifo bailout (deadlock path closed).
   TB: dynamic frame modeled + masked; ALL CHECKS PASSED.
2. MEASURED DEVICE MAP (devicefiles/): full fecc_far sequence over the
   scrubber range via SYNDROMEVALID-qualified ILA capture (2 windows,
   deterministic init): 94 columns, 3250 frames (top cols 18-55: 1316;
   bottom cols 0-55: 1934), ending exactly at end_frame 0x401BA9 - the
   inherited range config was correct. Healthy sweeps never visit 0x1C00+:
   all 0x653 lore is overrun artifact, now filtered.
3. FINAL CAMPAIGN (12 injections incl. bottom-half frames and words 0/100):
   zero recurrences; 11/12 corrected faster than the 40 ms poll; only the
   first-after-boot injection observable (708 ms). Caveat: "pre-poll
   corrected" trials were never captured at all - fast correction is the
   parsimonious reading given trial 1 and prior observed campaigns.
4. Operational note: heavy JTAG cycling occasionally wedges the PS DAP
   ("APB AP transaction error"); xsdb `targets -set 1; rst -system` recovers.

## Bounded-pass + geometry session (2026-08-29 pm, commits 8d30572..)

SIM (multi-column core_tb: two columns w/ real FAR jump, invalid tail):
ALL 7 CHECKS PASSED incl. COLUMN-LAST and cross-column corrections. Bounded
passes (exact per-column frame counts from the measured geometry, op-done
exit, pass-end flush) close the col-last coverage hole; scan-driver
accept-then-wait handshake ends the missed-start/double-done race class.
Registered shared frame attribution fixed a -0.46ns timing violation
(final build WNS +0.51).

SILICON (18-injection hardware-timed campaign, latency_campaign_18x.log):
+ CORRECTION LATENCY MEASURED: 36-40 us typical (hardware us-counters,
  STATUS[31:24]); 36 us mid-column, 40 us column-last.
+ Column-last injections LAND (non-minor-0 FARs work - the old "canonical
  addressing" requirement was another artifact of the fixed bugs) and are
  DETECTED with exact parameter-tracking syndromes; capture FAR across the
  column jump = next column base + 1, as the geometry predicts.
+ Bottom-half frames, words 0 and 100: corrected.
OPEN ITEMS (next session):
- Column-last CORRECTION convergence on silicon: top-half 0x0A23 recurred
  ~2 trials before clearing; bottom-half 0x400A23 still recurring at campaign
  end. Detection exact; suspect the correction-pass calc/subgroup interplay
  for the last frame of a bounded pass. Sim passes the same case - another
  model-vs-silicon delta to close (candidate: flush-on-done group field /
  handler-driven pass geometry for the error group).
- detect-latency counter saturates (harness bug in the Start->capture edge
  logic); correct-latency counter is good. Detection latency is anyway
  bounded by the sweep (10-20 ms measured).
- 0x1C02-region artifact still captured occasionally (capture path is
  unfiltered by design; frequency much reduced) - residual stop-latency
  reads at the col-55 pass end, to quantify.

## RESOLUTION of the col-last convergence gap (2026-08-29 pm)

ILA on a col-last correction cycle: entry perfect (frame 0x23, w10/b3,
single=1) but the group FIFO field read 0xA80 - the NEXT column. Root cause:
the flush wrote delayed_far's group, which for a pass-end error has already
shifted into the next column on silicon (one extra chain shift at op end that
the TB model does not emit). The handler-driven correction pass then scanned
the wrong column (calc = no pattern) and the EDC no-op-corrected the clean
frame one column over (0x0AA3) forever.

FIX: entry_group latched at STORE time (from the shared attribution), used by
both flush writers - immune to any trailing pulses. TB regression ALL PASS.
SILICON (collast_final_validation.log, WNS +0.15): col-last 0x0A23, 0x0C23,
0x400A23 each seen exactly once then quiet 13-14s under live scan ->
CORRECTED at 40us; mid-column 36us unchanged. #46 item 1 CLOSED.

Detect-latency counter: deprecated (multiple Start sources + sticky-capture
occupancy make the Start->capture edge measurement unreliable); detection
latency is bounded by the sweep (10-20ms measured). Correct-latency counter
(STATUS[31:24]) is the good instrument: 36us mid-column, 40us column-last.
