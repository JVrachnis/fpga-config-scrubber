# Branch feature/param-2d-hardening — silicon checkpoint (2026-08-29)

Build: 619d5b2, WNS +1.285, all 7 FSMs fsm_safe_state (Synth 8-5552 x7).

## Campaign (final_campaign2.tcl)
12/12 injections corrected, zero recurrences. 7 first-detections observed via
JTAG polling (mean 1745 ms — JTAG poll/ack loop bound, same as master campaigns);
5 corrected before the first poll could see them.

Note: the script's per-line "RECURRING!" label is an artifact — it demands >900 ms
of quiet inside a fixed 2.5 s window, impossible when first detection lands after
1.6 s. All flagged lines were `seen x1`. A dedicated 20 s live-scan recheck
(scan counter provably advancing) confirmed all four flagged FARs quiet: CORRECTED.

## Timing story
safe-state on the previously KEEP-blocked FSMs (mark_debug implied KEEP) initially
broke timing to WNS -1.598: handler state/FIFO fed the pcalc->arb->controller
words_to_access carry chain combinationally. Two register cuts, both bit-exact or
protocol-safe, fixed it with margin *better* than master (+0.15 -> +1.285):
1. handler `busy` registered from next_state (identical waveform).
2. controller ×101 adder fed from num_r (1-cycle-registered muxed num_of_frames;
   all clients lock command >=1 cycle before level-start).

Background census: 0x1C02 x13/30s + scattered one-shot 0x653-class events —
identical signature to master. Validity filter keeps them out of the handler.

---
## Step 2: golden-store byte parity + regen-on-error (2026-08-29, later)

Design decision: byte-parity DETECTION (32+4 = 36 b = exact RAMB18 native width)
instead of the memo's SECDED — SECDED(39,32) would have doubled BRAM per bank,
and correction-in-place is unnecessary because golden parity is always
regenerable from the scrubbed-clean frames. Policy: perr during a compare pass
-> pass poisoned (handler discards it, no correction from untrusted calc data)
-> `initialized` dropped in pcalc idle -> full golden re-init (<15 ms) -> the
frame error (if any) is re-detected and corrected against fresh golden.

Races found and fixed in the bench (closed-loop TB, golden corrupted through a
sim-only fault hook in pchk_dualportmem):
1. Dropping `initialized` right at parity_calc_done let the poisoned pass's own
   stop_read_mem re-set it (thinking it had completed an init pass) — infinite
   poison loop. Drop moved to the idle state.
2. The comb FSM left idle (scan's start_parity_calc) in the same cycle the
   poison was consumed, so the arbiter request for the re-init was never
   raised — pcalc parked in read_mem forever. idle transition now waits for
   pass_poisoned='0'.
3. Scan driver had no mid-flight re-init handling — parks in SCAN_WAIT_INIT
   whenever parity_initialized drops, like boot.
4. The fault hook's read-modify-write initially defeated BRAM inference
   (595k FDRE / 584k LUT explosion, DRC UTLZ-1) — moved inside
   translate_off so synthesis sees a pure BRAM template.

Verified: TB golden-upset check green in all three configs (S2G64/S4G64/S4G128)
— detection on next scan pass, re-init, zero frame writes during handling,
normal 2-D correction afterwards. Silicon: WNS +1.171, RAMB18 36->37 (total
cost of protecting every golden bank), init=1 on hardware (parity encode/decode
proven by the golden init sweep itself), 12/12 campaign + live-scan recheck
clean.

Residual risk (documented): a frame error present at the moment of a golden
re-init is absorbed into fresh golden; a single-bit frame error still self-heals
afterwards (correction of the single-frame case flips (synword,synbit) from the
Frame-ECC syndrome — golden is not consulted), but an even/multi-bit frame
error concurrent with a golden BRAM hit in the same group can be frozen.
Probability ~ (correction latency 40 us) x (BRAM SEU rate): negligible; a
readback-CRC layer would close it. Next: step 3, TMR of handler indices.

---
## Step 3: TMR with feedback voters (2026-08-29, later still)

Scope chosen by consequence analysis rather than blanket triplication:
- pcalc `initialized` (1 b): a 0->1 flip during the init sweep truncates golden
  silently (parity-consistent, wrong content -> wrong corrections) - the worst
  failure class in the design. A 1->0 flip merely costs a spurious 15 ms re-init.
- handler `syndrome_mem_last_entry_index` + `syndrome_group_first_entry_index`
  (7 b each at G=64): longest-lived bookkeeping; a flipped index mis-attributes
  stored syndromes and can turn a correction into a wrong-frame write.
- All 7 FSMs already carry fsm_safe_state; `scan_group_addr` self-heals within
  one sweep via the wrap test; ICAP-op state is transient (op fails, retried).

Pattern: 3 DONT_TOUCH copies, bitwise majority voter, and a feedback path -
every copy re-samples the vote at the top of each clock (specific assignments
override), so a flipped copy is scrubbed within one cycle without any
additional control logic.

Verified:
- TB (sim_tmr_flip hook, translate_off internals): copy-A flips at rest are
  masked with zero disturbance (no init drop, no write-backs), and a flip in
  the middle of an error-handling episode still ends in a normal correction.
  Matrix green: S2G64 / S4G64 / S4G128.
- Netlist: get_cells confirms 3 + 21 + 23 TMR flip-flops present after route
  (DONT_TOUCH honored; the extra sg_first FFs are fanout replicas).
- Silicon: WNS +1.355, campaign 12/12, live-scan recheck quiet, init=1.

Branch summary - all three hardening steps plus parameterization are now
implemented, bench-verified, and silicon-regressed:
  1. safe-state FSMs (x7)            - illegal-state recovery
  2. golden store byte parity        - detect + regenerate (<15 ms), 1 RAMB18
  3. TMR feedback voters             - highest-consequence registers
Remaining from the memo (optional): watchdog + self-reset (step 4); the
readback-CRC layer that would close the golden-absorption residual risk.

---
## The stuck-correction hunt (2026-09-01): two latent correction-path races
## found and fixed; one column-specific residual still open

The watchdog build's campaign showed frame 0x0A00 recurring uncorrected.
Systematic probing revealed the failure was never watchdog-related (diag 0x01
sightings were the 3-bit ec counters wrapping through zero - a reminder that
sparse diagnostics invite mythology). Eight ILA insertions later, two distinct
latent bugs stood proven, both predating the branch:

### Bug 1 - handler consumed straggler parity_calc_done pulses (FIXED)
The calculator pulses done at pass exit AND again at desync. The handler's
parity_calc state accepted ANY done pulse, so it routinely consumed the
trailing pulse of the very scan pass that detected the error, and started
error correction with STALE (zero) calc parity: the frame was read, "merged"
with zeros, and rewritten verbatim - forever. ILA proof: locked_far showed
start_error_correction firing at t=365 while the handler's own group pass ran
orphaned at t=924+. The scan driver received the accept-then-wait handshake
for exactly this in the bounded-pass rework; the handler never did. Fix: same
pattern - start_parity_calc held as a level, pass accepted only on a RISING
edge of the calculator's arbiter request, done honored only when accepted.

### Bug 2 - CORRECT_WITH_PARITY stream/calc misalignment (FIXED)
The parity-reconstruction write XORed the outgoing stream against
calc_word_rd_data addressed by a counter racing the controller's fetch
pipeline (the legacy "MUST BE SYNCHRONIZED ----- ONE CYCLE EARLIER" comment).
ILA caught the stream leading icap_current_word_index by 2 where the RTL
assumed +1: the equality never fired / the XOR grabbed the wrong word.
Phase-dependent by placement - campaigns passed for six years on placement
luck. (The SBU path had the same class of bug; both ILA5/6 captures showed
byte-swapped verbatim write-back, e.g. 0x50020000 -> 0x0A400000 word for
word with no flip anywhere.) Fix: a MERGE_S state rotates the frame buffer
once between the read and write ops, folding calc parity in at a self-paced
4-cycle-per-word rhythm; the calc read latency is a fixed RTL pipeline,
identical in sim and silicon. The write op then streams the merged buffer
verbatim. The SBU path got a local stream-position counter for its mask.

Bench: the closed-loop TB reproduced bug 2 the moment the handler handshake
shifted episode phase (cross-column check regressed with EVOLVING syndromes),
and gained a repeat-error-same-frame check; all checks green in all three
configs after both fixes. Silicon: double-injection stress across 14 frames
improved from 10/28 to 26/28 corrected.

### OPEN: column-19 residual
Frames in top column 19 (FAR 0x0980 group) still loop uncorrected on both
post-fix builds - constant syndrome (verbatim write-back) - while the ILA
shows a now-textbook episode: stragglers ignored, pass accepted on request
edge, correct 0x0980..0x09A3 sweep, calc populated with real diff data. The
correction content is still wrong for this one column, and intermittent
first-after-boot failures on other columns share the signature. Current
suspicion: the algorithm state machine's calc parity-bit bookkeeping (it
clears calc bits during syndrome processing) racing the merge's calc reads,
possibly interacting with the partial column 18 (first_far 0x901). Evidence
archived: /tmp ILA CSVs 5-9 copied below, stress/probe scripts in vivado/.
One column of 94, injector-provoked; detection is unaffected.

### Final-build campaign (post-fixes, WNS +0.960)
10/12 corrected before the first JTAG poll could observe them (the two fixes
also removed the multi-second "detection latencies" of earlier campaigns -
those were repeated failed-correction cycles, not detection delay). The two
failures were both injections into frame 0x0A00 - the residual column for
this placement (col 19 on the previous two builds, col 20 here), consistent
with the open per-placement residual above. Board left freshly programmed,
init=1, scan advancing.

### Residual narrowed (2026-09-01, session 2): whole-column, column-last exempt
ILA of the FIRST post-boot episode (ila_ep10, virgin boot + trap): the stuck
episode is TEXTBOOK - pass accepted on the request rising edge, correct
0x980..0x9A3 sweep, real golden-read data (561 nonzero reads), pass_poisoned=0,
pmem_word_rd_perr=0. Control flow is perfect; the written correction content
is simply wrong. So both race fixes hold - this is a third, separate mechanism.

Decisive minor-sweep (single-bit 0x08 into successive minors of column 19):
  0x0980 minor 0  STUCK
  0x0981 minor 1  STUCK
  0x0982 minor 2  STUCK
  0x0991 minor 17 STUCK
  0x09A3 minor 35 ok  <- COLUMN-LAST frame, the only one that corrects
=> the WHOLE column mis-corrects; the column-last frame (separate measured-
   geometry attribution path) is exempt.

Interpretation: a single-bit error should take the SBU path (pure syndrome
flip, golden never consulted). Its failure means these frames are being
mis-classified as needing 2-D parity reconstruction - i.e. the handler's
subgroup/single_frame bookkeeping believes the subgroup holds >1 frame when it
holds one, routing a lone error through the parity path, which then writes the
wrong bit. The column-last frame escapes because its attribution (and thus its
subgroup index) comes from the geometry lookup, not the plain FAR-1 path that
the rest of the column shares.

Why it moves per placement (col 19 / 20 / 24 across builds): the mis-
classification is tipped by a timing-marginal path, so which column manifests
depends on placement - but within a manifesting column it is total and
deterministic, and always spares column-last.

STATUS: OPEN, narrowed. Next concrete step (no rebuild needed to reason):
audit syndrome_handler single_frame_subgroup_flag / single_frame_in_subgr and
the subgroup attribution for the plain-FAR-1 (non-column-last) frames -
specifically whether a stale flag from the prior group's pass survives into a
fresh single-frame column pass. A targeted ILA on single_frame_in_subgr +
subgroup + attr_r during a col-19 episode would confirm in one capture.
Value/cost: one injector-provoked column of 94, correction-only (detection
unaffected), so deferred rather than chased further this session.

### CORRECTION to the residual diagnosis (2026-09-01, session 3)
The "whole column 19 stuck, column-last exempt" reading was an ARTIFACT of
test ordering, and is hereby retracted. Controlled repetition shows:

  * which frame sticks is simply WHICHEVER FRAME IS INJECTED FIRST after the
    scrubber starts (col 19 / 20 / 24 across sessions = my first injection in
    that session, not a property of those columns);
  * every subsequent error corrects normally, even in the same column and
    even while the first frame remains dirty. Proof, one campaign run on one
    bitstream: #01 (0x0A00) STUCK and never reverted, #02..#07 into other
    frames all "pre-poll corrected", #08 (0x0A00 again, still dirty) STUCK;
  * the earlier minor-sweep that looked column-wide was self-inflicted: it
    REVERTED each stuck frame, which re-triggers an episode on a frame the
    handler is already looping on, so the broken state persisted across the
    sweep. A run without reverts shows one failure, then clean behaviour.
  * not elapsed time: a 30 s warm-up before the first injection changes
    nothing (both the immediate and the warmed run fail on shot 1).

RESTATED DEFECT: the FIRST correction episode after scrubber start fails,
leaving that one frame permanently dirty; because a dirty frame re-detects on
every sweep, the handler then loops on it, which is why an already-broken
session looks worse than it is. All later errors are corrected.

Consequences for the earlier ILA evidence: ep10 (a first-episode capture)
showed the pass sweeping the right column with real golden data, no poison,
no perr, yet sg0 calc ending ~all-zero -> the merge XORed zero -> verbatim
rewrite -> constant syndrome. That is consistent with the first episode
running its compare pass against a calc/golden state that has not yet been
exercised once. Suspects, in order: (a) calc parity memory never written
before the first correction pass (its BRAM is zero-initialised, and the
first pass's subgroup-accumulator init may not cover every word), (b) the
`initialized` 0->1 transition at the end of the init sweep leaving the first
post-init pass in an in-between mode, (c) first-episode syndrome-memory
index bookkeeping (offset 0 / last_entry 1 path).

Reproducer, exact and reliable: program, start scrubber, inject ONE single-bit
error, poll - it will not be corrected. Do not revert; inject elsewhere - that
one corrects. This makes the next ILA capture deterministic (trigger on
start_error_correction, take shot 1), which is now in flight.

### First-episode capture (ila_first.csv): merge is innocent, calc memory is EMPTY
Deterministic reproducer (program -> start -> ONE injection) captured with the
merge instrumented. Result, unambiguous:

  * single_frame_in_subgr = 1, correct_using_parity = 1  (routing correct)
  * MERGE_S executes flawlessly: all 101 words, phases 0->1->2->3, grant held
    the whole time, frame_buffer data streaming correctly
  * calc_word_rd_data = 00000000 for EVERY ONE of the 101 words

So the merge XORs zero into the frame -> verbatim rewrite -> error persists ->
constant syndrome forever. The MERGE_S rework is not at fault; the calculated
parity memory simply contains nothing when the correction reads it.

This also explains why only the FIRST error fails: for a CLEAN column the
correct value of calc IS zero (current XOR golden = 0), so a stale/never-run
compare pass is indistinguishable from a clean one. The first episode reads
calc that no error-bearing pass has yet written; later episodes find calc
populated by the preceding episode's pass.

Next capture (in flight, ila10): parity calculator WRITE port and merge READ
port in one window, pre-trigger covering the whole compare pass, to establish
whether the episode's pass actually wrote non-zero calc for this subgroup and
the read simply missed it (address/bank or timing), or whether the pass never
wrote at all.

---
## ROOT CAUSE FOUND AND FIXED (2026-09-01): the watchdog was eating the golden store

The residual was self-inflicted - a defect in the step-4 watchdog, not in the
2-D algorithm, the geometry, or the merge.

**Mechanism.** The watchdog counted "cycles without a completed parity pass"
with an 84 ms timeout, and counted them unconditionally. The fault injector is
paced by JTAG (tens of ms per register write), so during an injection it owns
the ICAP long enough to starve the counter past the timeout. The watchdog then
asserted its recovery reset in the middle of the injection. Because that reset
cleared `initialized`, the core ran a full golden re-initialisation - RE-READING
CONFIGURATION MEMORY THAT NOW CONTAINED THE JUST-INJECTED ERROR AND LEARNING IT
AS GOLDEN. From that moment calc = golden XOR current = 0 for that subgroup: the
merge XORed zero, the frame was rewritten verbatim, the syndrome never changed,
and the frame was permanently uncorrectable.

**Evidence chain.**
1. ila_first.csv - MERGE_S executes perfectly (101 words, phases 0-3, grant
   held) but calc_word_rd_data is 00000000 for every word.
2. ila_pass.csv - the compare pass's FINAL calc[sg0] is identically zero across
   all 101 words, including word 10, while the frame is demonstrably in error.
   calc = 0 can only mean golden already contains the error.
3. dip_mon - "init-low sightings" jump from 0 (idle) to 45 DURING an injection.
4. Bisect - a build with wd_timeout_cycles = 0 (watchdog disabled) corrects
   5/5 of exactly the injections that failed 5/5 with it enabled.

**Fix (three parts).**
1. Hold-off: the watchdog no longer counts while another ICAP client owns the
   port (injector request/grant, algorithm request/grant) or while the handler
   is busy. It judges only the scrubber's own progress.
2. Timeout 84 ms -> ~2.7 s. The watchdog exists to escape a PERMANENT hang, so
   a multi-second detection latency costs nothing, while a short timeout trips
   on legitimate long ICAP ownership.
3. Golden is PRESERVED across a watchdog reset (`preserve_init`). This is the
   safety-relevant part and matters in flight, not just on the bench: the golden
   store lives in BRAM and survives a soft reset, so rebuilding it from
   configuration memory that may still hold an uncorrected upset is never right.
   Had the watchdog ever fired in orbit with an upset pending, it would have
   canonised that upset. It now resumes against the golden it already trusts.

**Bench.** The TB's watchdog check was passing on an artifact (scrub_diag is
cleared by core_reset, so `init` dips for 16 cycles regardless). It now times
the dip: ~16 cycles = golden preserved (pass), ~74 us = a full re-init ran
(fail). Result: "watchdog fired, core recovered with golden PRESERVED (down
150 ns)". All checks green in all three configs.

**Silicon, final build (WNS +1.120).**

    first-injection test        5/5  corrected   (was 0/5)
    double-injection stress    28/28 corrected   (was 10/28 pre-session,
                                                  26/28 after the race fixes)
    12-injection campaign      12/12 corrected, no recurrences

The per-placement "sticky column" is gone. RESIDUAL CLOSED.
