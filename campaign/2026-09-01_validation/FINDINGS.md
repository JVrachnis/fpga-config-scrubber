# Validation round, 1 Sep 2026 — statistics, timing, capacity, real-data coverage

Purpose: replace hand-picked 12–28 injection claims with statistics, characterise
the timing, establish how many upsets can be handled *at once* and over what
window, and evaluate every code configuration against the **real** heavy-ion
upset distribution.

Build under test: `feature/param-2d-hardening` @ `4aa5208`+, WNS +1.12 ns,
core 1613 LUT / 1746 FF / 37 RAMB18.

---

## 1. Randomised campaign — 150 injections

> **Superseded (2026-09-03 review, §13.1).** This run's own log reads
> `detected=2, corrected=150`; the verdict did not require detection. The
> honest number is in §13.

Vectors generated from the **measured** device geometry (`vivado/campaign_vectors.tcl`,
seeded, reproducible): 147 distinct frames, 94 bottom-half / 56 top-half, words
0–100, random bit positions.

| pattern | what it exercises | n | corrected |
|---|---|---|---|
| `single` | 1 bit — horizontal Hamming path | 100 | **100** |
| `adj2` | 2 adjacent bits in one word — word field XOR-cancels, the defining 2-D case | 25 | **25** |
| `sep2` | 2 non-adjacent bits, same word | 10 | **10** |
| `adj3` | 3 adjacent bits (odd) | 8 | **8** |
| `adj4` | 4 adjacent bits (even) | 7 | **7** |
| **total** | | **150** | **150 (100 %)** |

The scan counter advanced across *every* injection (live-scan verification, 150/150).
Background census over 30 s before the campaign: 13–14 distinct FARs, all outside
valid configuration space, none in the scrubbed range.

### 1a. A false negative in the harness — the third of its kind

The first two runs of this campaign reported 142/150 and 139/150. Neither was real.
The quiet-check window opened *immediately* after the detection window, so the
legitimate single detection of the injected error was still latched and counted as
a recurrence. Evidence:

* every "failure" passed 3/3 on isolated retest (live **and** paused) — 24/24;
* pausing the scan during injection did not help (139/150) and failed on
  *different* vectors, ruling out an injector/scrubber write race;
* a probe that settles 500 ms before observing recorded **60/60 clean**, with a
  hit distribution of exactly zero — no stale captures, no dirty frames
  (`quiet_window_probe.log`);
* with the settle added, the full 150-vector set scores 150/150.

This is the third time in this project that a verification check, not the design,
was the thing at fault (after the scan-pausing rechecks and the watchdog's
init-dip check). The pattern is consistent enough to be worth stating as a rule:
**when a result is anomalous, instrument the instrument first.**

---

## 2. Timing (`timing.log`)

> **Superseded (§13.2).** The 3.3 ms sweep below is arithmetic on the frame
> rate; the measured revisit period was 2.127 s. Fixed in Rev. 1.10.

| quantity | value | how obtained |
|---|---|---|
| JTAG register read | **2.49 ms** | 200 reads timed — this is the instrument floor and bounds everything else |
| Golden initialisation | **≤ 8–9 ms** measured; ~3.3 ms by construction | first poll after the start kick already sees `init=1`, so the true value is below one JTAG round trip; 3251 frames × 101 words × 10 ns = 3.28 ms |
| Full device sweep | **~3.3 ms** (arithmetic), **< 9 ms** (bounded by the init measurement) | the frame counter advances > 100 counts/ms, faster than JTAG can sample without aliasing — see caveat |
| Correction latency | **80 µs** typical (9/20 samples); 11/20 read saturated | hardware µs counter, `STATUS[31:24]`, 4 µs/LSB |
| Detection latency | bounded by one sweep (~3.3 ms) | every frame is read once per sweep |

**Caveats, stated rather than hidden.** The 8-bit frame counter increments faster
than the 2.49 ms JTAG floor allows sampling, so the delta-counter method aliases
(1/2/4/8/16 ms dwells all returned 104–142 counts) and cannot resolve the sweep
directly; the sweep figure rests on the init measurement plus arithmetic. The
correction-latency counter saturates at 255 × 4 µs = 1020 µs and is read
asynchronously, so it yields a typical value, not a distribution. Earlier builds
measured 36/40 µs on this counter; the merge-state rework added a pass over the
frame buffer, and 80 µs is consistent with read + merge + write + the group's
compare pass. A proper distribution needs the counter widened and latched
per-event — noted as future work rather than estimated.

---

## 3. How many upsets "at once", and what "at once" means

### The window
Two upsets are concurrent, from the corrector's point of view, only if both are
present when their group's compare pass runs. That window is **one sweep
(~3.3 ms)** plus the correction episode (~80 µs). Anything separated by more than
that is handled as two independent events.

### The capacity
The scarce resource is *the subgroup's vertical parity*, and only
**even-multiplicity** frames consume it:

* **odd multiplicity** (1, 3, … bits in a frame): the Frame-ECC syndrome locates
  the bit directly. No vertical parity involved, so these are unlimited — any
  number of frames, any groups, bounded only by throughput (~80 µs each).
* **even multiplicity** (2, 4, … bits): the word field XOR-cancels, so the frame
  must be reconstructed from its subgroup's parity. **At most one such frame per
  subgroup per window** — with S = 2, two per column, one per subgroup.
* different columns are independent groups and never interfere.

### Why this could not be fully staged on silicon
`capacity.log` and `cap2.log` show every multi-frame case correcting, including
ones theory says should fail — because **concurrency cannot be created with this
injector**. `isolation.log` shows why: the scan-pause bit gates only the scan
driver (`enable => not scan_pause`); the syndrome handler's compare pass and the
correction write are *not* gated. The injector's own ICAP read reveals the error
to Frame-ECC immediately, so it is corrected within microseconds — long before a
second JTAG injection (~65 ms) can land. Concurrent multi-frame upsets therefore
remain **simulation-verified only** (the closed-loop bench covers two frames in a
subgroup and four adjacent frames at S = 4), and this is a property of the test
harness, not a gap in the design. Staging it on hardware would need a gate on the
correction path, not just the scan.

---

## 4. Coverage against the real heavy-ion data (`coverage.py`)

Replay of the CERN 2018 (46,812 CLB upsets, 922 readback captures) and GSI 2019
databases through a model of each configuration. Unit = one upset-bearing frame
within one accumulation window.

**CERN 2018 — 32,691 upset-bearing frames**

| configuration | corrected | uncorrected | **mis-corrected** | coverage |
|---|---|---|---|---|
| none (no scrubbing) | 0 | 32,691 | 0 | 0 % |
| Frame-ECC only (SEM-like) | 31,598 | 895 | **198** | 96.66 % |
| vertical parity only | 29,353 | 3,338 | 0 | 89.79 % |
| **both (this design)** | 32,512 | 179 | **0** | **99.45 %** |

**GSI 2019 — 7,101 upset-bearing frames**

| configuration | corrected | uncorrected | **mis-corrected** | coverage |
|---|---|---|---|---|
| none | 0 | 7,101 | 0 | 0 % |
| Frame-ECC only | 6,993 | 106 | **2** | 98.48 % |
| vertical parity only | 4,900 | 2,201 | 0 | 69.00 % |
| **both** | 7,063 | 38 | 0 | **99.46 %** |

Three things worth drawing out:

1. **Single-bit ECC alone actively mis-corrects.** On odd multiplicities ≥ 3 the
   Hamming syndrome decodes to a position that is *wrong*, so the scrubber writes
   a new error into an already-damaged frame: 198 frames at CERN, 2 at GSI. The
   mixed code never does this — it either corrects or declines.
2. **Neither dimension is sufficient alone.** Vertical parity by itself is *worse*
   than ECC alone (89.8 % / 69.0 %), because it fails whenever two frames share a
   subgroup. The value is in the combination, and the numbers quantify it.
3. **The residual is the documented limit**: ≥ 2 errored frames in one subgroup
   needing the parity, with differing syndromes — 179 frames (0.55 %) at CERN.

### Scaling to continuous scrubbing — the honest correction
Those figures use the **beam readback interval as the window: a median of 40.8 s**,
which is ~12,000× longer than our 3.3 ms sweep. They therefore describe a system
that scrubs only every 41 s, and are a *worst case* for one that scrubs
continuously. At the measured CERN CLB rate (0.907 upsets/s):

| sweep | λ (upsets per sweep) | P(≥ 2 in one sweep) |
|---|---|---|
| 3.3 ms | 3.0 × 10⁻³ | ~4.5 × 10⁻⁶ |
| 10 ms | 9.1 × 10⁻³ | ~4.1 × 10⁻⁵ |

and the coincidence that actually defeats the code — two even-multiplicity frames
in the *same subgroup of the same column* within one sweep — is far rarer still.
Under continuous operation at that flux the design's effective coverage is
essentially 100 %; the 99.45 % figure is the pessimistic bound.

---

## 5. What remains unproven

* Concurrent multi-frame correction **on silicon** (harness limitation above;
  simulation-verified).
* A correction-latency *distribution* (counter saturates; needs widening).
* Direct measurement of the sweep period (needs a wider counter or a free-running
  timer readable over AXI).
* Everything here is single-device, room-temperature, injector-driven. Beam
  validation of the completed design remains future work.

## Artefacts
`campaign_150_final.{log,csv}` · `campaign_150_run1_harness_artifact.log` ·
`campaign_150_paused.log` · `quiet_window_probe.log` · `capacity.log` ·
`cap2.log` · `isolation.log` · `timing.log` · `coverage.py`
Scripts: `vivado/big_campaign.tcl`, `campaign_vectors.tcl`, `hits_probe.tcl`,
`capacity.tcl`, `capacity2.tcl`, `isolation.tcl`, `timing_char.tcl`, `retest.tcl`.

---

## 6. Test mode added (Rev. 1.9) — and what it bought

Two instruments were built in response to the limits hit above.

### `HOLD_CORRECTION` — CTRL bit 6
Withholds Frame-ECC error flags from the syndrome handler, so nothing is
detected, no episode starts, and nothing is written back; upsets **accumulate**.
Scanning continues and the golden store is untouched, so release is not
disruptive. This is the mechanism that was missing: scan-pause gates only the
scan driver, whereas the corrector is reached by the injector's own ICAP read.

Verified on silicon: **0 captures while held**, normal correction after release
(`conc.log`). All seven staged multi-frame cases then corrected — 2 odd frames
in a subgroup, 2 even frames in different subgroups, 2 even in the *same*
subgroup, 4 odd in one subgroup, 1 even + 3 odd, 8 odd across four columns, and
2 even per column across two columns.

### 32-bit instrumentation — CTRL bits 10:8 select, read at `0x1C`
Select 0 keeps the historical `CAP_SYN` layout, so every existing script is
unaffected. Selects 1 and 2 (`us_timer`, `frames_ctr`) give the measurement the
8-bit counter could never provide, because it wraps faster than JTAG can sample:

> **985–986 frames/ms → 1.01 µs/frame → full device sweep (3251 frames) = 3.30 ms**

against 3.28 ms predicted from 101 words at 100 MHz. This replaces the estimate
in §2 with a direct measurement, and it fixes the number that matters most: the
sweep period is both the detection bound and the coincidence window of §3.

### Honest status of the remaining counters
`det_ctr`, `cor_ctr`, `t_det`, `t_cor` (selects 3–6) infer their events from the
capture flag and the `SCRUB_DIAG` done-counter. Both are ack- and mode-dependent
and they do **not** track reliably — staged runs reported 0–1 corrections where
N were expected, while the same runs demonstrably corrected every frame. They
need dedicated single-cycle pulses exported from `scrubber_ip` at syndrome-store
and at `error_correction_done`; that is a small, well-defined change and the
correct next step. Until then they are documented as unvalidated and detection
accounting should use captures with periodic acknowledgement.

Consequently the concurrent-capacity question of §3 is **still not settled**:
the staging mechanism now exists and works, but the instrument that would count
what happened during a staged episode does not yet. The prediction to test, once
the pulses exist, is unchanged — odd-multiplicity frames unlimited, even-
multiplicity frames one per subgroup per sweep.

### Also learned
The capture path is single-entry and **sticky**: a background event latches and
blocks later captures until acknowledged. Any observation loop must ack on every
poll; loops that ack only after a hit will silently miss detections. This
explains an anomaly in an earlier probe and is worth stating in the TRM.

Build: WNS **+1.358 ns** with both facilities in, core unchanged in function.

---

## 7. Counter fix attempt — resolved partly, and one item honestly still open

### Fixed: the pulses now come from the source
`scrubber_ip` exports two single-cycle pulses (`detect_pulse`, `correct_pulse`)
instead of the AXI block inferring events from `ecc_captured` and the
`SCRUB_DIAG` done-counter. Wiring verified end to end
(`scrubber_ip` -> `scrubber_wrapper` -> AXI interface).

### Still open: the detect/correct counters do not count
Three attempts, each rebuilt and measured on silicon:

1. sample `fecc_eccerror_filt` on the rising edge of `SYNDROMEVALID` — counted
   almost nothing (0-3 where N expected);
2. latch the flag anywhere within the pulse, emit on its falling edge — same;
3. sample at exactly the handler's own point (`sv_d`, i.e. the delayed valid,
   which is what `syndrome_handler` line 254 tests) — still zero.

Meanwhile the same build passes the stress campaign **28/28**, so detections and
corrections are certainly happening; only the pulse fails to observe them. The
background `0x001C02` capture that the capture path reports is correctly *not*
counted — it is a masked/invalid frame and the validity filter excludes it — so
that particular zero is right.

**Next step, and the reason to stop reasoning:** three hypotheses about signal
timing have now been wrong in a row. The correct move is to put an ILA on
`fecc_syndromevalid`, `fecc_eccerror`, `fecc_eccerror_filt`, `detect_pulse` and
`error_correction_done` and *look* at the relationship, exactly as was done for
the correction-path races and the watchdog. Everything else in this project that
was resolved by measurement had first survived a run of confident wrong guesses;
this one has earned the same treatment rather than a fourth guess.

### What the instrumentation does deliver
`us_timer` and `frames_ctr` (selects 1 and 2) work and are the source of the
sweep measurement in §6 — 985-986 frames/ms, full sweep **3.30 ms**, matching
the 3.28 ms arithmetic. Those are the numbers the timing and coincidence-window
claims rest on, and they are sound.

### Consequence for the capacity question
Unchanged from §6: the staging mechanism (`HOLD_CORRECTION`) works and is
verified, but the counter that would measure what happens inside a staged
episode does not, so concurrent capacity remains **measured only indirectly**
(via capture polling, which showed every staged case correcting) and the
even/odd multiplicity prediction is still unconfirmed on silicon.

Build with all of the above: WNS +1.078, stress 28/28.

---

## 8. Digging into the counters — what the five-way probe found

Rather than a fourth retiming guess, `scrubber_ip` was given a probe counting
**five candidate conditions at once**, so the silicon could say which is true:
raw ECCERROR at the SYNDROMEVALID edge / one cycle later, the same two for the
*filtered* error, and `error_correction_done`. One build, five hypotheses.

### Result

```
                       raw@edge   raw@d    filt@edge  filt@d  corr_done  frames
idle (fresh)             61953    61953        0        0        0       524719
idle +1 s                61953    61953        0        0        0      1594089
after 1 injection        61953    61953        0        0        0      1615917
  +1 s                   61953    61953        0        3        1      2131046
after 10 more           123909   123909        3        3        1      2888629
```

Three things fall out of this, and two of them matter more than the counter.

**1. `raw@edge` and `raw@d` are identical.** ECCERROR spans both sampling
points, so the three failed retimings were never a phase problem. The filter is
what gates the pulse, not the phase.

**2. The background artifact rate is ~12 % of frames read** — 61,953 raw ECC
events per 524,719 frames, not the "one or two a second" the capture path had
suggested. The validity filter correctly rejects essentially all of them (the
2026-08-29 census showed they decode outside configuration space), which is why
`filt` stays near zero. The design is behaving correctly; our *picture* of the
background was wrong by three orders of magnitude, because we had only ever
counted it through a register that shows one event at a time.

**3. The capture register is therefore a poor instrument.** It is single-entry
and sticky, and with 12 % of frames raising a raw event it is almost always
occupied by an artifact. In the landing test below, `capture_seen` was 0 for
**all 16** injections — not because nothing happened, but because the register
never had room to show it.

### The consequence for our claims — stated plainly
A campaign verdict of "no recurring capture at frame+2" is satisfied by three
different situations: the error was corrected, the error was never planted, or
the capture register was busy. It cannot distinguish them. What it *can* still
do is catch a **persistently broken** frame, because such a frame re-triggers
every sweep and eventually wins the register — which is exactly how the watchdog
defect was found (46 captures on one frame).

So the honest restatement is:

> The 150/150 campaign demonstrates that **no injected frame was left
> persistently in error**. It does not, by itself, prove that 150 errors were
> planted and individually corrected.

That is a weaker claim than §1 made, and §1 should be read with this caveat.
The 2-D correction results that rest on *observed* detections (the stuck-frame
diagnoses, the ILA-captured episodes, the closed-loop bench) are unaffected.

### Injection landing rate
Measured with the filtered-detection counter, injecting into distinct valid
frames: **live 3/10, scan-paused 2/10, corrector-frozen 0/10** (`landing2.log`),
and 5/16 in the first run. Either the injector plants only ~25 % of the time, or
the filtered-detection counter under-counts for the same reason the pulse did.
These two cannot be separated with black-box counters — which is precisely the
boundary reached below.

### Where this stops, and why
Four build-and-measure cycles have now been spent on this counter. The evidence
says the remaining unknown is the *timing relationship between `attr_r`,
`masked_hit` and the error flag* — `attr_r` is registered from `fecc_far`, so
the filter is only valid in a narrow window, and both the pulse and possibly the
handler see it differently than assumed. That is a waveform question. The next
step is an ILA on `fecc_syndromevalid`, `fecc_eccerror`, `attr_r`, `masked_hit`,
`fecc_eccerror_filt` and `detect_pulse` — five signals, one capture, and it
settles both the counter and the landing rate at once.

Every other timing question in this project (the correction races, the frame
attribution identity, the watchdog) was settled that way after a run of
confident wrong guesses. This one has earned the same treatment.

---

## 9. The waveform — the counter was right all along

ILA on `fecc_syndromevalid`, `fecc_eccerror`, `fecc_eccerror_filt`, `masked_hit`,
`detect_pulse`, `attr_r` and `fecc_far`, triggered on a raw ECCERROR rising edge
(`ila_filter.csv`, 4096 samples ≈ 41 µs).

```
idx   sv err filt mask dp    attr_r    fecc_far
511    0  0   0    1   0    0001c00   0001c01
512    1  1   0    1   0    0001c00   0001c02   <== trigger
513    0  1   0    1   0    0001c01   0001c02
...    (err stays high, mask stays high, filt stays 0)

over 4096 samples: sv=40  err=3584 (87%)  filt=0  masked_hit=3684 (90%)  detect_pulse=0
samples with err=1 AND masked_hit=0 : 0
```

### What this shows

1. **`fecc_eccerror` is a LEVEL, not a per-frame pulse.** It sits high for 87 %
   of the window. Every retiming hypothesis assumed a pulse; none of them was
   the problem.

2. **The window is the invalid region.** `fecc_far` runs 0x1BA8 → 0x1BA9 →
   0x1C00 → 0x1C01 → 0x1C02 — column 56, past the last valid column (55), which
   is exactly the archived `0x1C02` artifact address. ECCERROR is permanently
   asserted while the readback traverses that region.

3. **The validity filter is doing precisely its job.** `masked_hit` is high
   throughout, `fecc_eccerror_filt` is zero throughout, and there is **not one
   sample** in 4096 where a raw error passed the filter. `detect_pulse`
   correctly never fires.

### Consequence: two earlier conclusions were wrong, and the counter was not

* The "~12 % of frames raise a raw ECC event" reading in §8 is **withdrawn**.
  It is not 12 % of frames scattered across the device; it is a *contiguous
  invalid region* where the level sits high and which the scan crosses once per
  sweep. The count was real, the interpretation was not.
* The detect/correct counters are **correct and working**. Four retimings were
  chasing a bug that did not exist. When a genuine valid-space error occurs the
  counters do register it — as they did after the one injection that landed in
  §8 (`filt@d = 3`, `corr_done = 1`).

### What that leaves open — and it is a better question
If the counters are sound, then the zero detections during staged injections
mean those injections **genuinely did not plant an upset**. The landing-rate
measurements (5/16, then 3/10 live, 2/10 paused, 0/10 frozen) are therefore
measurements of the *injector*, not of the instrument. The open question moves
from "why doesn't the counter count?" to **"why does the injector plant only
~25 % of the time?"** — which is a far more consequential question, because it
is the tool every campaign in this project has relied on.

That also sharpens §8's caveat rather than removing it: campaign verdicts still
cannot distinguish corrected from never-planted, and now we have direct evidence
that never-planted is common.

### Next step
Probe the injector itself: ILA on the fault-injection channel's arbiter request
and grant, the ICAP write path and the injector FSM state, during a sequence of
injection commands. The question is whether it loses arbitration, aborts, or
completes a write that does not take effect.

---

## 10. Why injections don't land: the scan loop owns the ICAP

### The measurement that settles it
`STATUS` bit 4 (`ICAP_FREE`, new) reports when no scrubber client is requesting
the configuration port:

```
ICAP free while scanning normally  :  0 / 20 samples
ICAP free with TEST_FREEZE asserted: 20 / 20 samples
```

**The 2026 continuous-scan loop holds the configuration port 100 % of the time.**
The fault injector requests it, never wins a grant, and its Start is silently
dropped. Nothing reports the failure.

This explains the whole chain of anomalies:

* landing rate ~25 % from JTAG, and unchanged by the busy/synced handshake;
* the 2021 **PS application** (`injector_ap.elf`) also plants nothing today
  (`psrun.log`: `filt_det=0`, its own `ECC_far`/`ECC_SYNDROME` globals read 0) —
  so the fault is not in how we drive the injector from Tcl;
* and why that same application *worked* in 2019-21: there was no scan driver
  then. The scrubber was reactive, so the port was usually free. **The 2026
  continuous-scan loop — the feature that made the core autonomous — is what
  broke the injector.**

### What was added
`TEST_FREEZE` (CTRL bit 7) withdraws *every* scrubber ICAP request — parity
calculator and correction path both — parks the scan driver, and withholds error
flags. `ICAP_FREE` (STATUS bit 4) is the handshake: assert freeze, poll until
the port is free, inject, release. The golden store is untouched, so releasing
is not disruptive.

### Status: the port is freed, but injections still do not land frozen
`fc2.log`, single frame 0x001200, capture path (independent of the debug mux):

```
baseline            : 0 target captures
PLAIN injection     : 1 target capture   <- landed and was corrected
FROZEN injection    : 0 target captures
```

So freeing the *arbiter* is necessary but not sufficient. The likely remaining
piece: withdrawing requests does not make the ICAP **controller** desync and
hand over the physical port, so the injector receives a grant while the
controller still owns `ICAPE2` and its writes go nowhere. The freeze needs to
drive the controller to a desynced/released state and report that, rather than
merely dropping the arbiter request.

### Why this matters beyond the test harness
Two of this project's claims depend on it:

* every 2026 campaign verdict rests on injections that we now know land
  perhaps a quarter of the time — §8's caveat is not academic;
* and it is a genuine design observation, not only a bench artifact: a
  continuously scanning scrubber starves every other ICAP client. Any system
  that also needs the port (partial reconfiguration, an external scrubber, a
  readback service) will hit exactly this. The arbiter has priorities but the
  scan loop simply never yields, and nothing in the design reports the
  starvation.

### Next step
Extend `TEST_FREEZE` to force the ICAP controller through a desync and expose
"physically released" in `ICAP_FREE`, then re-measure the landing rate frozen vs
plain. That is the one change needed to make the injector deterministic, and
with it the concurrency experiments of §3/§6 finally become possible.

---

## 11. Mid-correction fault injection (freeze the state, inject, resume)

Goal: plant a bit flip *while a correction episode is in flight*, so the
scrubber's response to a second upset arriving mid-repair can be observed.
That needs the machine to stop exactly where it stands, the configuration port
to become usable by the injector, and the machine to resume from the same state.

### 11.1 Why the first two attempts failed

**Attempt 1 — `TEST_FREEZE` alone (withdraw the scrubber's ICAP requests).**
The injector was granted the port (`busy` 0 -> 1) but never completed. Probe
`freeze_pr.log`:

```
=== C. TEST_FREEZE only (bit7) ===
  before Start     busy=0 free=1 idle=0
    during Start   busy=1 free=1 idle=0     <- injector granted
  after Start      busy=1 free=1 idle=0     <- and stuck there forever
```

**Attempt 2 — split clock domains** (`icap_ctrl`/`icap_arb` on a free-running
`clk_free`, decision logic on a gated `scrub_clk`). Same hang, plus the frame
counter kept advancing during a freeze.

Root cause, from `icap_controller.vhd`: withdrawing a channel's `arb_request`
makes the arbiter re-select immediately, so that channel's `stop` line stops
being muxed into the controller. The controller is left in
`READ_FRAMES_SEQUENCE_S`, which only exits on `stop_command = '1'`. It therefore
keeps running - now against the *new* owner's frame address - and never returns
to `SYNCED_S`, so the injector waits on a port that never comes back.

### 11.2 The fix: an ordered hand-off

`freeze_handoff_p` in `scrubber_ip.vhd`, on `clk_free` so it still sequences
while the core clock is gated:

1. `test_freeze` asserts `tf_stop` -> `stop` is ORed onto both scrubber
   channels **with their requests still up**, so the stop actually reaches the
   controller: `READ_FRAMES_SEQUENCE_S -> STOP_SEQUENCE_S -> SYNCED_S`.
2. Wait for `icap_busy = '0'` (controller parked in `SYNCED_S`).
3. Only then assert `tf_release`, dropping the requests so the arbiter can hand
   a *synced and quiet* port to the injector.

`ICAP_FREE` (STATUS bit 4) now means "released **and** parked", which is the
condition the injector actually needs. Build: WNS +1.241, no new resources.

### 11.3 The freeze is real

`freeze_mp.log` §A - freeze with no injection at all:

```
running: sc=206 free=0
frozen:  handoff=1 sc 183 -> 183 -> 183  (deltas 0, 0)
         init=1 (golden store survived)
thawed:  sc 233 -> 188 (delta 211)
```

800 ms frozen with zero configuration-port activity, `parity_initialized`
intact, and normal operation on release.

> Note: `scan_counter` counts SYNDROMEVALID edges in the **AXI** domain, so it
> is only a freeze witness when nothing else is driving the port. It moves
> during a frozen *injection* because the injector's own readback drives it.
> An earlier run misread this as a failed freeze.

### 11.4 Mid-correction injection works

`freeze_mp.log` §B - a correction episode staged and held with
`HOLD_CORRECTION`, then frozen, then a **second** upset planted in the same
frame while the first repair is in flight:

```
staged upset detected under HOLD_CORRECTION: 1
frozen mid-episode: free=1 init=1
after release: captures at frame = 1  init=1
```

The second flip lands, the episode resumes from its exact state, and the golden
store is not disturbed. This is the capability that was missing.

### 11.5 Freezing is *required*, not merely convenient

Paired frozen/plain trials on the campaign vectors (`freeze_mf2.log`):

| mode | detected |
|---|---|
| frozen | 6 / 20 |
| plain  | 1 / 20 |

> **Superseded by §12.6 and §13.** Both arms were measured with a 1200 ms
> window on vectors 39% of which were unreachable. On reachable vectors with an
> adequate window, plain injection lands as well as frozen (§12.5, §13.3).
> Freezing is required for *mid-correction placement*, not for planting.

### 11.6 The residual misses are deterministic, and are not the freeze

Repeat trials show a clean split - never a mixed result (`freeze_md.log`,
`freeze_th.log`):

```
0x40110C  w30   1 1 1   3/3        0x40109C  w55   0 0 0   0/3
0x40110C  w61   1 1 1   3/3        0x401022  w41   0 0 0   0/3
0x001603  w32   1 1 1   3/3        0x400E18  w54   0 0 0   0/3
0x4019A0  w66   1 1 1   3/3        0x400102  w61   0 0 0   0/3
```

Factorial sweep (`freeze_fa.log`) separates the two candidate causes:

* **word index is irrelevant** - 18/18 words 0..100 land in a good frame;
  `0x40110C` lands at both word 30 and word 61;
* **frame address decides** - and it is not the device half. FAR bit22 = 1 is
  fine (`0x40110C` -> captured at `0x40110E`, the same +2 readback offset as the
  bottom half), so an earlier "top half is broken" reading was wrong.

Three further measurement artifacts were found and corrected:

1. **Observation window.** At 1200 ms several vectors read as misses that are
   3/3 at 2500 ms. The 150/150 campaign's longer settle was load-bearing.
2. **The "undo" injection was planting fresh errors.** The scrubber corrects the
   upset within ~80 us, so re-injecting the same XOR mask to "clean up" created a
   *new* fault and polluted the following trial.
3. ~~`sep2`/`adj2` masks are invisible to this detector by construction.~~
   **Retracted 2026-09-03 (§14.1).** Two bits in one word are *visible*:
   `ECCERROR=1, ECCERRORSINGLE=0`, captured at 4-5 ms and corrected. The
   "invisible" inference came from vectors that were in unreachable columns.
   What is true is that the ECC cannot *locate* an even-multiplicity error;
   that is the vertical parity's job, and it did it. Four adjacent bits gave no
   capture at all.

### 11.7 What this changes

§8's caveat - that a campaign verdict cannot distinguish *corrected* from
*never planted* - is now addressable: with the hand-off, "planted" is
deterministic per frame, so a non-detection is a property of the frame, not of
the injector. The concurrency-capacity experiments of §3/§6 are unblocked.

**Still open:** enumerate which frame addresses are injectable and cross-check
that set against the measured valid-frame map, so that campaign vectors are
drawn only from frames known to be reachable.

### 11.8 Scripts

`vivado/midproof.tcl` (freeze proof + mid-episode injection),
`vivado/factorial.tcl` (word vs frame separation),
`vivado/missdiag.tcl` and `vivado/tophalf.tcl` (determinism, both halves),
`vivado/midfinal2.tcl` (paired acceptance), `vivado/farcheck.tcl` (capture-FAR
offset), `vivado/probe.tcl` (arbiter/injector handshake).

---

## 12. The injectable-frame map

§11.6 left one thing open: injection outcome is deterministic per frame, but
which frames? Answered by sweeping the FAR space with the frozen injector.

### 12.1 Method

One frozen single-bit injection per frame, 2500 ms observation, verdict =
capture at FAR+2. Two shortcuts were tried and rejected:

* **Batching** 4 frames per freeze cycle. Two frames with a known 3/3 verdict
  read as 0 in a batch - with the corrector free *and* with it held under
  `HOLD_CORRECTION`. Abandoned; per-trial costs ~4 s, so a 244-point grid is
  ~15 min anyway.
* A **1200 ms** window. Several frames read 0 at 1200 ms and 3/3 at 2500 ms.
  This alone accounts for most of §11.5's low absolute numbers.

`vivado/injmap2.tcl` (sparse grid, 228 points), `vivado/injmap3.tcl` (every
column 0..60 x 2 minors x 2 halves, 244 points, plus no-injection controls).

### 12.2 Result: injectability is a function of the FAR column alone

Uniform across minors and (almost) across halves:

```
columns  18-27, 34-55   injectable, both halves
columns   0-17, 28-33   never injectable
column       56         FALSE POSITIVE - see 12.3
columns  57-60          beyond cols_per_row_c = 56; excluded
```

`half=1, cols 43-55` came back 0 in one of four sweeps - a minor-dependent soft
spot, so those columns are used in the bottom half only.

This **matches the previously measured device map** (top columns 18-55) and adds
a detail that map did not have: the **28-33 gap**.

### 12.3 Columns >= 56 are an artifact, not a discovery

The sparse sweep reported columns 56/58/60 as 36/36 injectable, which would put
real frames outside the configured `cols_per_row_c = 56`. Control trials - the
identical freeze/thaw sequence with the **injection step skipped**:

| col | injected | control |
|---|---|---|
| 20, 24, 40, 52, 55, 58, 60 | 1 | **0** |
| 56 | 1 | **1** |

Column 56 fires with nothing planted. It is the out-of-device artifact region
(`0x001C02` is already in `masked_frames_c`); it raises ECC events on its own,
so a capture at FAR+2 there proves nothing. Columns 57-60 have clean controls
but sit outside the configured scan geometry, so they are excluded from vectors
pending a separate check.

### 12.4 The map predicts the earlier results

Applied to the 20 frozen trials of §11.5, the column rule alone predicts
**18/20** outcomes. Both mismatches are `half=1` in the 43-55 band - exactly the
soft spot the sweep independently flags.

Applied to the old vector file: only **92 of 150** vectors (61%) sit in
injectable columns, and 50 are `sep2`/`adj2` masks that the ECC capture flag
cannot see by construction. Unreachable columns used: 1-16 and 28-33.

### 12.5 Corrected vectors, and the acceptance run

`vivado/gen_vectors.py` emits `campaign_vectors_reachable.tcl`: 150 single-bit
vectors drawn only from injectable columns, minors capped at 31.

Paired acceptance on those vectors, 2500 ms window (`reachable_acceptance.log`):

| mode | before (old vectors, 1200 ms) | after |
|---|---|---|
| frozen | 6 / 20 | **29 / 30** |
| plain  | 1 / 20 | **29 / 30** |

Both misses were at minor 34-35. A CLB column holds 36 frames, so that is the
top boundary of the minor range; the generator now caps minors at 31.

### 12.6 What this settles

The §8 caveat is closed. A campaign verdict on these vectors distinguishes
*corrected* from *never planted*, because "planted" is now a known property of
the target frame rather than a coin flip. The concurrency-capacity experiments
of §3/§6 can be run on `campaign_vectors_reachable.tcl` and their non-detections
read as real.

Note that plain (unfrozen) injection also reaches 29/30 once the vectors are
reachable and the window is long enough. Freezing remains **required** for
mid-correction work - placing an upset at a chosen point inside a repair - but
it is not required merely to plant one.

---

## 13. After the review: honest numbers, a 600× scan bug, and the freeze cleared

Executing `REVIEW_2026-09-03.md` in order. Every item below is on silicon with
the recovery word (`CAPFLAGS[23:19]`: watchdog-fire parity, `init_drops`,
`handoff_timeout`, `tf_release`) added in this round so that re-inits and
watchdog resets are no longer invisible.

### 13.1 The 150/150 campaign, re-run with a verdict that requires detection

`vivado/campaign_honest.tcl`: a vector passes only if it is **detected** (first
capture at FAR+2 within 2.5 s), **corrected** (≤1 further capture in 800 ms of
free scanning after a 300 ms settle), **clean** (`init` stayed 1, `init_drops`
unchanged), and **no watchdog fire**. Plain injection, reachable vectors.

| scan | detected | corrected | clean | PASS | detection latency (median / max) |
|---|---|---|---|---|---|
| linear (Rev. 1.9) | 147/150 | 147/150 | 150/150 | **147/150** | 2013 ms / 2133 ms |
| geometry-aware (Rev. 1.10) | 148/150 | 147/150 | 149/150 | **147/150** | **5 ms / 8 ms** |

Failures, both runs: `0x40111E` (col 34, minor 30) and `0x001B1C` (col 54,
minor 28) never detected — those columns have 30 minors in the geometry table;
the generator capped minors at 31 instead of using the table (fixed: per-column
count minus 2). On the fast scan one further vector, `0x401498`, was detected,
then re-captured 37× and `init_drops` went +1: a golden re-init while the error
was present — the §5 signature, caught by the new verdict, once in 150.

So the correct statement for the thesis is **147/150 detected and corrected with
no golden re-learn**, with the three exceptions named. Not 150/150.

### 13.2 The scan was walking 2.1 million addresses that do not exist

While characterizing post-thaw recovery (13.3) every top-half frame was detected
5 ms after thaw and every bottom-half frame ~2030 ms after. A full timeline of
captures with one upset held (`period_linscan.log`) showed the same frame
revisited every **2.127 s ± 3 ms**, with a burst of out-of-device artifacts
(column 56, then columns 191/444/697/966 ≈17 ms apart — 250 columns × 64 frames
× 1.01 µs) at each wrap.

`scan_driver_proc` stepped `scan_group_addr` by 128 linearly from `0x000900` to
`0x401BA9`. On this part that passes through column indices 56–1023 and row
indices 1–31 of the top half before reaching `0x400000`: ~32,800 groups × 64
frames ≈ 2.1 M readbacks per pass, of which 3251 are real. The "3.30 ms sweep"
in §2 and in the TRM was 3251 × 1.01 µs — correct arithmetic on a false premise.

Fix (Rev. 1.10, ~10 lines): when the stepped column field exceeds
`cols_per_row − 1`, jump to the other half. Pass ≈ 94 × 64 × 1.01 µs ≈ 6 ms by
construction, <17 ms measured (`period_geomscan.log`: re-captures on every
JTAG poll). Detection latency in 13.1 dropped from 2013 ms to 5 ms median.

Consequences: every latency, coincidence-window and "upsets per sweep" figure
derived from 3.3 ms was ~600× optimistic for Rev. ≤1.9 and is approximately
right for Rev. 1.10. The §8 "scan loop owns the ICAP" finding was a symptom of
the same bug: the port was busy reading nothing 99.8% of the time. The column-56
background burst is gone.

### 13.3 Post-thaw recovery: clean (review item 2 retired)

`thaw_char.log`. Freeze/thaw with nothing planted, ×5: scan resumes in 2–4 ms,
`init_drops` +0, watchdog parity unchanged. Freeze, inject, thaw, ×8: every
upset **corrected**, +0 drops, no watchdog. Thaw into `HOLD` then release, ×8:
same. The ~2 s latencies that prompted the review's concern were 13.2, not a
recovery path. §11.4's "resumes from its exact state" stands, now measured.

One script bug found on the way: the capture-ack proc wrote a bare `CTRL=0x1`,
silently dropping `HOLD_CORRECTION` on the first ack. That made HOLD look
broken (`period3.tcl` before the fix: upset seen at pass 1 and 2, gone at 3).
`lib.tcl` now preserves the CTRL base on ack; HOLD holds indefinitely (8/8
passes over 16 s).

### 13.4 The injector lands exactly one upset per grant

`pair_geomscan.log`, on the fast scan so trials cannot contaminate each other:
two injections in one freeze, four pairs × four variants (45 ms gap, wait for
`busy=0`, 300 ms gap, reversed order): **the first lands, the second never
does, 15/16.** This is what the batching attempt in §12.1 was seeing. Cause is
inside `fault_Injection.vhd` (a second `Start` under the same grant is not
honoured); not root-caused this round.

**Resolved the same day** (`pair_variants.log`, `pair_reqfirst.log`): it is the
*protocol*, not the FSM. Writing request (CTRL bit 1) and start (bit 2) in the
same AXI word works for the first injection after a hand-off and fails for later
ones; raising request first and start ~20 ms later lands both, 16/16 across all
gap/order variants. A desync pulse between injections also works; toggling
`icap_ready` does not. `lib.tcl`'s `inject` now does request-then-start. The
hold-and-re-freeze method below remains the way to plant N upsets without any
being repaired in between.

Procedural method, verified (`multi.tcl`): thaw into `HOLD` between injections and
re-freeze with HOLD kept — one hand-off per upset. **N = 2, 3, 4, 6, 8 upsets
planted and all seen while held, 8/8.** On release, N−1 are corrected within the
first pass and the last one within 2–4 s (`multi_stuck.log`), for every N. The
concurrency-capacity experiments of §3/§6 are unblocked with this method; the
2–4 s tail on the last upset is a real property of the concurrent path and is
the next thing to look at with an ILA.

### 13.5 Geometry, closed

`geom_probe.log`. Columns 28–33 (both halves) and bottom 0–17, which the
geometry table lists with 36 minors: injection under `HOLD` with every FAR
collected for 3 s produces **no capture anywhere** — not at FAR+2, not nearby.
The frames read back with valid ECC and the injector's write does not take (or
takes without ECC effect). Either way: not injection targets. Excluded.

Columns 56–64: "injected=1, control=0" on the new scan for all nine — but the
scan no longer visits them, so those captures are the injector's *own readback*
of out-of-device addresses tripping FRAME_ECCE2, not a planted-and-scanned
error. §12.3's column-56 verdict stands with that mechanism now identified.

### 13.6 Housekeeping from the review

`vivado/lib.tcl` (shared board library: hand-off *asserted* by `freeze`, DAP
recovery in `select_arm`, CTRL-preserving ack); `handoff_timeout` sticky;
`scan_counter`/`frames_ctr` comments corrected (they count port activity from any
client); §11.5 marked superseded in place; TRM revision table, register map and
sweep section rewritten (Rev. 1.10); `gen_vectors.py` uses the per-column minor
table.

### 13.7 Closing the review list

* `TEST_MODE_G` generic on `scrubber_wrapper` (default true). With it false the
  BUFGCE is not generated and the three test bits are tied off; out-of-context
  synthesis of the wrapper confirms **0 BUFGCE / 0 BUFG** cells
  (`prod_synth_testmode_off.log`, `prod_util_testmode_off.rpt`: 2911 LUT,
  2577 FF, 20 BRAM). The 2021 standalone `scrubber_ip_wrapper.vhd`, untouched
  since import, had been uncompilable since `clk_free` was added; fixed.
* Rev. 1.10 test build: WNS +0.223. Freeze/thaw ×5 and freeze-inject-thaw ×8
  all clean at 5 ms (`thaw_char_rev110.log`); `campaign_honest.tcl` on 40
  vectors from the per-column-table generator: **40/40** detected, corrected,
  clean (`campaign_honest_rev110_40.log`).
* Thesis (new chapter, 69 pp.), defense deck (23 slides), Greek thesis (new
  chapter, 20 pp.) and TRM (Rev. 1.10) carry this round.

Still open: the 2–4 s tail on the last of N concurrent upsets (ILA); the
concurrency-capacity campaign itself; a remote for the repository.

---

## 14. Concurrency capacity — the breaking point, measured

The experiment §3 and §6 could not run. Method: one hand-off per upset under
`HOLD_CORRECTION` (§13.4), release, watch 6–8 s with the live core word
(`core_live`, Rev. 1.11: `wd_fires`, handler busy, algorithm/pcalc request and
grant, ICAP busy, init/poisoned, scan state — readable over AXI at ~10 ms).
Geometry of the build: group = column, S = 2 subgroups (minor mod 2), G = 64.

### 14.1 First, a retraction: two-bit upsets are visible

`precheck_multiplicity.log`, plain injection into a reachable frame:

| mask | kind | first capture | flags (eccsingle, ecc, crc) | verdict |
|---|---|---|---|---|
| `0x08` | single | 4 ms | 1,1,0 | corrected |
| `0x18` | adj2 | 4 ms | **0,1,0** | corrected |
| `0x8080` | sep2 | 5 ms | **0,1,0** | corrected |
| `0x38` | adj3 | 5 ms | 1,1,0 | corrected |
| `0xF000` | adj4 | — | — | **not seen** |

§12.1 item 3 and the same sentence in the thesis said two-bit-in-one-word masks
"XOR-cancel the syndrome and are invisible to the capture flag". Wrong: the
7-series frame ECC is SECDED over the frame; a double error is *detected*
(`ECCERROR` without `ECCERRORSINGLE`) and not *located*. The inference had been
drawn from vectors that were in unreachable columns. Retracted in FINDINGS,
thesis, Greek thesis, review and generator. Four adjacent bits gave no capture;
whether the vertical parity quietly corrected it is not known.

### 14.2 Capacity (`conc_A_to_H.log`, `conc_E_G_live.log`)

| case | set | result |
|---|---|---|
| A | N single-bit upsets in N distinct columns, N = 1, 2, 4, 8, 12, 16 | all corrected within the first pass, every N |
| B | 2 singles, same column, different subgroups | corrected |
| C | 2 and 4 singles, same column, **same subgroup** | corrected (ECC locates each) |
| D | 1 even-multiplicity (adj2) frame | corrected |
| F | 2 adj2 frames, same column, different subgroups | corrected |
| E′ | adj2 + single, same subgroup | corrected (single first by ECC, then the adj2 alone) |
| H | 8 adj2 frames in 8 columns | all corrected |
| **E** | **2 adj2 frames, same subgroup** | **both dirty, 3/3 repeats, two columns** |
| **G** | 4 adj2 frames, 2 per subgroup | all 4 dirty |

This is exactly the code's construction: odd-multiplicity frames are located by
the ECC without limit; an even-multiplicity frame needs its subgroup's vertical
parity, and **one such frame per subgroup** is the capacity. With S = 2 that is
two per column, one per parity.

### 14.3 What happens at the limit is a livelock, not a hang

Live-word timeline for E over 8 s (`conc_E_G_live.log`): `wd_fires` +0,
`init` 1, `poisoned` 0 throughout. The handler is busy (`sh=1`) ~90 % of the
time with the parity calculator requesting and granted; it drops to idle for
40–100 ms every 0.5–1 s, during which the scan runs (`scan=RUN`), re-detects the
same two frames, and re-enters. **The algorithm channel never requests** — no
write is ever issued, so there is no mis-correction. The upsets stay; the
scrubber retries forever and the rest of the device is scanned at ~10 % duty.

An uncorrectable subgroup should be marked and skipped after a bounded number
of attempts, restoring full scan rate and exposing a "beyond capacity" status
bit. That is the next design item; it is not a safety defect (nothing is
written) but it is a coverage defect for everything else on the device.

### 14.4 The 2–4 s tail of §13.4: not reproduced

On this build, with either injection protocol (request-first and the old
simultaneous one), mixed-half, bottom-only and top-only sets of four singles
all correct within the first pass, 0/9 tails (`conc_halves.log`,
`livecheck_tail.log`). The 3/3 tails of §13.4 were on the previous build. Left
as *unreproduced*; the live word is in place if it recurs.

### 14.5 Two instrumentation notes

* `core_live` needs CTRL[10:8] nonzero as well as bit 12 (`0x1200`); with bit 12
  alone the read mux returns the historical overlay, which is how a first run
  produced "wd+7" from syndrome bits. Fixed in `lib.tcl`.
* "planted N/N" under HOLD is poll-limited: two upsets in the same column arrive
  1 µs apart every pass and the single-slot capture latch always shows the lower
  minor. It is an observation artifact; the correction results above are not
  affected.

---

## 15. Configuration matrix on silicon

Until this section every silicon number in this file was one configuration:
S = 2, G = 64, hardened. `vivado/matrix.sh` builds each configuration (edits the
two package constants and the watchdog generic, ~3 min when the machine is
otherwise idle), programs it, and runs period, the 150-vector honest campaign
and the S-aware capacity campaign; `matrix_report.py` makes the table.
`campaign/2026-09-03_matrix/MATRIX.md`, one directory per configuration with
build log, timing and utilization reports, bitstream and campaign logs.

### 15.1 The table

| configuration | LUT | FF | BRAM | WNS | pass | campaign PASS/150 | latency med/max | capacity: k even-mult. frames in one column | 2 in one subgroup | coverage CERN / GSI (model) |
|---|---|---|---|---|---|---|---|---|---|---|
| **S2G64** (reference) | 3289 | 3114 | 20 | +0.97 | <17 ms | **148** | 5 / 6 ms | 1,2 ok; **3 → 2 dirty, livelock** | dirty, livelock | 99.45 / 99.46 % |
| S2G64, watchdog off | 3275 | 3108 | 20 | +0.79 | <17 ms | **149** | 5 / 6 ms | same | same | same |
| **S4G64** | 4005 | 3339 | 37 | +0.53 | <17 ms | **149** | 4 / 6 ms | 1,2,3,4 ok; **5 → 2 dirty, livelock** | dirty, livelock | 99.80 / 99.73 % |
| **S4G128** | 4063 | 3383 | 37 | +0.61 | <17 ms | **149** | 5 / 6 ms | 1,2,3,4 ok; 5 → livelock | dirty, livelock | 99.80 / 99.73 % |
| S8G64 | — | — | — | — | — | — | — | — | — | 99.87 / 99.79 % |

S8G64 **does not fit the XC7Z010**: 8832 LUT-as-RAM cells required against
6000 available (the per-subgroup memories exceed the 60 block RAMs and spill
into distributed RAM). The coverage column for it is the model only.

The campaign misses are two frames, both named: `0x00091B` (col 18, minor 27)
was not detected on any of the four configurations — a frame-specific
non-detection, not yet explained — and `0x40150C` on the S2G64 reference run
triggered three golden re-inits with its error present (the residual §5
hazard, 1 in 600 vectors across the matrix). Detection latency is 4–6 ms
everywhere: the scan pass is the same on every configuration, since S and G do
not change what is read.

### 15.2 What S buys, measured

The capacity result of §14 scales exactly as the code's construction says:
**S even-multiplicity frames per column, one per subgroup.** S = 2 holds two,
the third is beyond capacity; S = 4 holds four, the fifth is beyond capacity;
two in one subgroup are beyond capacity at any S. Beyond capacity the
behaviour is the §14.3 livelock on every configuration — handler busy 91–94 %
of the time, no write, no watchdog fire. The price of S = 4 is 17 block RAMs
(20 → 37) and ~700 LUTs; S = 8 is not available on this part.

Against the real beam data, S = 4 closes 64 % of the remaining uncorrected
events on CERN 2018 (179 → 64 of 32,691 upset frames) and 50 % on GSI 2019
(38 → 19 of 7,101).

### 15.3 What G buys, and what it needs

G = 128 changes neither latency nor per-column capacity (both configurations
with S = 4 behave identically) but it doubles the syndrome memory, and that is
where a second limit sits. Sixteen even-multiplicity frames released together
(four per column across four columns) left **4 dirty with a livelock on S4G64**
and **0 dirty on S4G128**. The syndrome store — `2·G` entries — is the
capacity for *how many groups can be in error at once*, independent of the
per-subgroup limit.

That constant had been a fixed 128 in the package. With G = 128 the handler's
"memory nearly full" test is true from the first entry and the scrubber hangs
on the first correction (`_pre_fix/S4G128_entries128/`: detected, never
corrected, handler busy forever). The bench had always used `2·G`; the package
now derives it the same way. **G must satisfy `syndromes_mem_entries ≥ 2·G`**,
and does by construction from Rev. 1.12.

### 15.4 Two hangs found by the matrix, one of them mine

The first S4G64 run went silent after 30 corrections. The live word showed the
algorithm's ICAP interface holding request and grant with the algorithm state
machine idle, the parity calculator requesting and starved, the scan frozen,
and the watchdog counter pinned at zero because "algorithm request high" was on
its hold-off list. Mechanism: the algorithm interface asserts `desync` while
idle and releases its request only when the controller reports desynced; the
controller honours a desync from `SYNCED_S` only while `operation_done` is set,
and that flag is cleared by every re-sync — so after any `data_aligned = 0`
re-sync the desync is never honoured and the port is held forever.

My first fix made the controller honour any desync in `SYNCED_S`. It broke the
scrubber within ~20 corrections on S2G64 (`_pre_fix/S2G64_baddesyncfix/`): the
algorithm interface's idle-time desync is muxed through the arbiter on every
arbitration pass, so the controller now desynced on every pass. Reverted the
same hour. The fix that stands is on the algorithm side — release the request
after 4096 cycles if the desync has not been honoured; the next episode
re-syncs on entry — plus the watchdog hold-off now requires the algorithm to
actually be busy (`err_corr_busy`), so a request held by an idle algorithm is
the hang the watchdog exists for and no longer exempt. Live-word fields for the
arbiter (state, selected channel, one-hot, grant register) were added at the
same time (Rev. 1.12) so the next one is read, not reasoned.

### 15.5 Not done

The self-upset campaign (`selfupset.tcl`, targets from the logic-location
file) and the beam-event replay (`replay.tcl`, 655 real events per S, each
tagged with the model's prediction) are written and unrun; both need the board
for ~1.5 h each. The `0x00091B` non-detection wants an explanation. Mark-and-skip
for a subgroup beyond capacity (§14.3) remains the open design item, now with
the matrix showing it is the same livelock on every configuration.

---

## 16. Self-upset, mark-and-skip, and the beam replay

### 16.1 Self-upset: flipping the bits that are the scrubber

The hardening layers of §5 had only ever been tested by simulation hooks
(flip a golden word, flip a TMR copy). The silicon test is to flip the
scrubber's *own* configuration bits and see whether it survives and heals.

Target list: Vivado's essential-bits mask (`bitstream.seu.essentialbits`),
aligned to frame addresses through the logic-location file (which gives the
bitstream offset of every frame holding a scrubber flip-flop; frames of a
column are consecutive at 3232 bits each). Targets are the essential bits of
every frame in the columns that hold scrubber logic — bottom half, columns
19–52, 436,231 essential bits in 465 frames — restricted to injectable
columns, with non-essential bits of the same frames as a control arm
(`selfupset_ebd.py`, `selfupset.tcl`). Per trial: one bit, plain injection,
2.5 s to be detected, then corrected/clean checks, then a scan-alive check;
after a not-seen, a known-good frame is injected to distinguish "no effect"
from "scrubber blind". DEAD and BLIND reprogram the board and continue.

`selfupset_S2G64_300.log`, 300 trials (293 essential, 7 control):

| outcome | essential | control |
|---|---|---|
| **corrected by the scrubber itself** | **249 (85 %)** | 7 / 7 |
| no observable effect in 2.5 s (restored) | 20 (7 %) | — |
| DEAD — scan stopped, reprogram | 16 (5.5 %) | — |
| BLIND — scanning, no longer detecting | 3 (1 %) | — |
| detected, not cleanly corrected | 5 (2 %) | — |

Three of the DEADs took the AXI slave with them (PS bus hang → APB error →
DAP wedge; the JTAG library now reconnects, resets and reprograms
automatically). The two DEADs seen first were both in word 45 of their frame —
the clock-row region — which no register-level hardening can cover.

The honest self-protection number for this design on this part: **an
essential-bit upset in the scrubber's own fabric is corrected by the scrubber
85 % of the time and is fatal 6–7 % of the time.** Run 1 (`_run1_121.log`)
without the restore-after-not-seen step accumulated damage and ended in nine
consecutive not-seens; that artifact is why the step exists.

### 16.2 Mark-and-skip (Rev. 1.13)

`mark_skip_p` in `scrubber_ip`: an episode is "write-less" if the handler
went busy and idle again without the algorithm channel ever requesting the
port. Three consecutive write-less episodes on the same group mask that
group's Frame-ECC events for 2^29 cycles (~5.4 s) and raise `beyond_capacity`
(live word bit 3); the group is then retried. Episodes cut short by
`HOLD_CORRECTION`/`TEST_FREEZE` do not count (the first build counted them
and skipped a correctable column during planting — caught by the bench check
added for it and by `skipbisect2.tcl`).

Proof on silicon (`markskip_proof.log`): two even-multiplicity frames A, B in
one subgroup; after release `skip` rises, handler busy drops from ~93 % to
**0 %**; restoring A makes B visible (it had been planted all along — the
capture aliases to the lowest minor, §14.5); the skip expires at ~3.5 s; B,
now alone and correctable, is corrected. `conc_S2_rev113.log`: every
beyond-capacity case now shows handler busy 0 %.

### 16.3 Beam replay, S = 2

`replay.tcl 2 300` (`replay_S2_300.log`): 300 real events, every one with
four or more upset frames in one column (275 × 4, 18 × 5, 7 × 6 frames),
planted with one hand-off per upset under HOLD, released, watched 4 s; verdict
= no frame re-captured after 2.5 s, handler not busy, skip not raised.

**299 / 300 corrected on silicon.** The model had predicted 274: 26 events it
called uncorrectable were corrected. Cause: correction is *sequential*. The
single-bit frames in a subgroup are located by the ECC and repaired first,
after which a multi-bit frame is alone for the parity (case E′ of §14.2 in
the wild). The model's condition was "alone"; the right condition is "the only
multi-bit frame in its subgroup", which explains 24 of the 26 (the last two
are corrected beyond even that). `coverage.py` now uses it. Under the
validated rule the beam-data model gives, for the mixed code:

| S | CERN 2018 | GSI 2019 |
|---|---|---|
| 2 | 99.80 % (66 of 32,691 frames uncorrectable) | 100 % |
| 4 | 100 % | 100 % |

with the standing caveat that the model's window is the beam readback
interval, far longer than one 6 ms pass, so it over-states coincidence.

### 16.4 The one replay failure, and what it is

`CERN_0`: four single-bit frames in bottom column 19 — minors 8 and 9 in
word 50 (the frame's ECC-check word) and minors 26 and 27 in word 92. Every
single-bit frame is ECC-locatable; the model and case C say trivially
correctable. On silicon (`cern0_split.log`, `cern0_variants.log`,
`cern0_fresh.log`, `word50.log`):

* any single one of the four: corrected; each pair: corrected; three of them:
  corrected; single bits anywhere in word 50 including the check bits:
  corrected (syndromes `0x1001`/`0x1004`/`0x1020`, verified genuine — parity
  stays clean afterwards);
* **all four together in column 19: the last one is left, after three
  write-less episodes, and the skip fires** — reproducible from a fresh board;
* the same four in top column 44: corrected;
* after a *sequence* of such four-frame events in column 19, the handler
  enters a second regime — busy 100 % with the algorithm writing continuously
  — which a fresh board does not show for the same event.

So it is neither word 50 nor the subgroup rule: it is episode bookkeeping
across several corrections in one group, history-dependent, the class the
2026-08-28 index-desync fix belonged to. Reproducer: `cern0.tcl` case c. It
needs an ILA on the syndrome handler's memory indices; not attempted this
round. Word-50 upsets are 0.6–0.7 % of upset frames in the beam data; this
combination is rarer still, but it is the only replay failure in 300 and it is
deterministic.

### 16.5 Status

| claim | evidence |
|---|---|
| hardening on silicon | 85 % of essential-bit self-upsets self-corrected, ~7 % fatal (300 trials) |
| beyond-capacity behaviour | livelock → mark-and-skip, handler idle, retry after 5 s, proven end-to-end |
| real events | 299/300 corrected at S=2; model refined to the sequential rule, 297/300 agreement |
| open | 4-frame same-column history defect (reproducer in hand); `0x00091B` non-detection |

---

## 17. Hardness, layer by layer — what is demonstrated and what is not

The four hardening layers of §5 defend different things, and a comparison is
only honest if each is tested against the upset it defends against. This
section is the ledger. Where a layer's value is *not* demonstrated by any test
it says so; that turned out to be two of the four.

### 17.1 Configuration upsets in the scrubber's own fabric, watchdog on vs off

Same 300 essential-bit targets (§16.1), same order, on the Rev. 1.13 build
with the watchdog enabled and with `wd_timeout_cycles = 0`
(`selfupset_S2G64_300.log`, `selfupset_S2G64_wdoff_300.log`):

| outcome | watchdog on | watchdog off |
|---|---|---|
| corrected by the scrubber | 249 (85 %) | 268 (89 %) |
| no observable effect | 20 | 19 |
| DEAD (scan stopped) | 16 | 7 |
| BLIND (scanning, not detecting) | 3 | 4 |
| **recovered by the watchdog** | **0** | — |

Paired per bit, 37 of 300 targets changed verdict — 16 DEAD→corrected and 6
corrected→DEAD among them — so whether a given essential-bit hit is fatal is
**not deterministic**: it depends on when in the scan the flip lands, not only
on which bit. The two builds also place differently, so the essential-bit map
of one is approximate for the other; the 4–6 % fatal rates are therefore not
distinguishable, but the zero recoveries are not confounded by anything.

**Verdict: the watchdog gives no measurable protection against configuration
upsets in the scrubber's own fabric.** The hits that stop the scan take the
clock, the reset tree or the watchdog itself with them. Its domain is the
logic-hang class (§15.4's algorithm-channel hang) — and it caught that only
once its hold-off was qualified.

### 17.2 Golden-store byte parity

*Bench A/B* (`bench_golden_parity_off.log`, generic `golden_parity_check =
false`): the closed-loop run passes its first seven checks and then never
completes the golden-store-upset step — the corruption is never detected, the
re-init never happens, the dependent correction never finishes — where the
hardened build reports "golden-store upset detected on scan pass, re-init
triggered" and continues. **Demonstrated.**

*Silicon* (`bramupset.tcl`, block-type-1 frames of the 32 golden RAMB18s,
targets from the `.ll`): inconclusive. Where the flipped word was read on the
next pass, detection and full regeneration took **12–14 ms**; most flips were
not caught in 1.5 s and could not be shown to have landed. Two method
artifacts were identified and are the reason for the verdict: a block-type-1
frame spans a slice of every BRAM in the column, so the injector's
read-modify-write disturbs the live memories sharing the column unless the
core is frozen (it now is); and the fixed spot-check frames accumulated state
across trials (long runs of "dirty" that cleared on their own). A silicon
number needs a BRAM readback path and per-trial fresh spot frames.

### 17.3 TMR on the handler indices and `initialized`

*Bench A/B* (`bench_tmr_off_checks_still_pass.log`, generic `tmr_enable =
false`): **both TMR checks still pass with the voters bypassed.** The at-rest
flip lands on indices that are reset at the next episode start; the
mid-episode flip lands in a single-entry episode where `sm_last` is never
consulted. The checks do not discriminate. This is the §5 lesson a third time
— a check that cannot fail is not a test — applied to a layer I had counted
as verified. **Not demonstrated.** The check needs a multi-entry episode with
the flip between store and use; no silicon test is possible (flip-flop state
cannot be written through the configuration port).

### 17.4 `fsm_safe_state`

No test exists in either direction: the bench has no illegal-state hook and
silicon cannot inject one. **Not demonstrated.** Its cost is known (two
register cuts that improved timing); its benefit is an argument from the
attribute's semantics.

### 17.5 Mark-and-skip (Rev. 1.13)

Demonstrated end to end on silicon (§16.2): handler duty 93 % → 0 % at the
capacity limit, retry after expiry corrects what became correctable.

### 17.6 The ledger

| layer | defends against | demonstrated | how |
|---|---|---|---|
| golden byte parity | golden-store SEU | **yes** (bench); silicon inconclusive | A/B generic |
| watchdog | logic hang | **yes** for hangs; **no** for config hits | silicon 0/19 recoveries; §15.4 |
| TMR | index/flag SEU | **no** | existing checks pass with TMR off |
| safe-state FSMs | illegal state | **no** | no test exists |
| mark-and-skip | capacity livelock | **yes** (silicon) | §16.2 |
| scrubber vs its own config | config SEU in own fabric | 85–89 % self-healed, 4–6 % fatal, stochastic per bit | 600 trials |

Everything in this table is on `feature/param-2d-hardening` with the generics
`GOLDEN_PARITY_G`, `tmr_enable`, `wd_timeout_cycles` and `TEST_MODE_G`, so any
row can be re-run.

---

## 18. A discriminating TMR check, a frame readback path, and what it exposed

### 18.1 TMR — demonstrated after all

The new bench check (`core_tb.vhd`, "TMR discriminating check") stores two
syndrome entries in one group and lands the copy-A flip at five points after
the handler goes busy — inside the store, the parity pass and the correction —
so a wrong index has consequences. With the voters on: all five sub-trials
correct both frames (`bench_tmr_on_new_check_passes.log`). With
`tmr_enable = false`: **TIMEOUT at the first flip point, both frames never
corrected** (`bench_tmr_off_new_check_FAILS.log`). The check discriminates;
the §17.6 ledger row for TMR moves to **demonstrated (bench)**.

### 18.2 Frame readback (Rev. 1.14)

The injector already captures every frame it touches into its buffer. A
second BRAM port exposes that buffer over AXI (CTRL bit 13 with a nonzero
CTRL[10:8]; word index in `0x04`; data at `0x1C`). A mask-0 injection is a
read that writes the frame back unchanged, so `readframe` returns the actual
101 words. Verified: two reads of a frame identical; a single injected bit
shows as exactly that bit and only that bit; restoring it leaves no diff
(`rbtest.tcl`). ~1.5 s per frame over JTAG.

### 18.3 What the readback settled

* **Block-type-1 (BRAM content) frames read back with real content but writes
  to them do not take** — flip, read, no diff, plain or frozen. The silicon
  golden-store arm of §17.2 therefore never injected anything; its "regen"
  events were unrelated. Struck. The bench A/B is the golden-parity evidence.
* **`CERN_0` is a race.** With readbacks interleaved in the planting, all four
  bits land exactly and all four are corrected in one pass
  (`cern0_rb`). Without them it fails 3 of 4 setups. A logic-analyser item,
  labelled as such.
* **Invalid frame addresses corrupt real frames.** A read-modify-write at a
  minor beyond the column's count (my own list used minor 33 in 28- and
  30-minor columns) writes 5–79 wrong words into a neighbouring frame, frozen
  or plain (`frozencorrupt.tcl`: 2/24 in every arm, always the same two
  invalid addresses; 0/22 valid frames). Every target list must go through
  the per-column minor table — the third time this rule has bitten.

### 18.4 What the readback opened

Re-testing the twenty "not seen" self-upset bits with readback
(`notseen_rb`): most of them **killed the scrubber outright** on re-test (the
campaign had left it alive on the same bits — the per-bit outcome is
stochastic, §17.1), two left their bit in place with the scrubber dead, and two
showed the frame **rewritten in dozens of words while the scrubber stayed
healthy**. The last class would be the worst possible outcome — a silent
whole-frame mis-correction with a self-consistent ECC, invisible to the
capture flag. It is *not* established, because of the next item.

**A frozen read-modify-write on `0x400A23` (bottom column 20, minor 35, a
scrubber-own frame) corrupts that frame 2 times in 6** — 86 words once —
while plain operations on it never do, and while the same frozen operation on
22 top-half frames and on the neighbouring last-minor frames corrupts nothing
(`dyncheck2`, `lastminor`). The AXI interconnect's 64 `SRLC32E` read-data
FIFO cells sit in bottom columns 19–23, but a 172-frame census of those
columns found no frame whose content changes between two plain reads with
AXI traffic in between, so dynamic content is not the mechanism either. Open:
an injector/controller artifact confined to frozen operations on some
scrubber-own frames. Until it is explained, frozen injections into the
scrubber's own frames are suspect; the plain-injection self-upset campaigns
of §16–17 are not affected, and the frozen campaigns of §14–15 targeted
top-half frames outside the scrubber.

### 18.5 Ledger update

| layer | demonstrated | how |
|---|---|---|
| golden byte parity | **yes** (bench) — silicon not possible with this injector | A/B generic; block-1 writes do not take |
| watchdog | hangs yes; config hits no | 0/19 recoveries |
| TMR | **yes** (bench) | new discriminating check fails with voters off |
| safe-state FSMs | no | no test exists |
| mark-and-skip | yes (silicon) | §16.2 |

Scripts: `rbtest.tcl`, `rbtest2.tcl`, `cern0_rb.tcl`, `notseen_rb.tcl`,
`dyncheck*.tcl`, `frozencorrupt.tcl`, `lastminor.tcl`, `census.tcl`,
`bram_targets.py`, `bramupset.tcl` (void for block-1 targets).

### 18.6 The frozen-RMW "corruption", explained by the ILA — and every DAP wedge with it

ILA (`insert_ila12.tcl`, 21 probes on the ICAP controller, hand-off, injector
and both ICAP data buses, triggered on the injector's start;
`ila_rmw_clean.csv` / `ila_rmw_corrupt.csv`): the clean and the corrupting
read of `0x400A23` have an **identical** control sequence — re-sync after the
hand-off, the right FAR (`0x00400A23`, bit-swapped `000250C4` on the bus),
dummy frame, 101 data words, done. What differs is the data the device
returned for the same address. The frame holds the AXI interconnect's
`SRLC32E` read-data FIFO (64 cells at SLICE X0–X16, Y38–52 → bottom columns
19–24 and their top-half mirrors): its configuration bits *are* the last 32
words that went to the PS. Two plain `readframe`s look static only because
they issue an identical access sequence; a freeze in between changes the
history, so the "corruption" is the injector writing a stale FIFO snapshot
back into a live AXI converter — which then hangs the PS bus. That is the
DAP-wedge mechanism of the whole project, and the frame census of §18.4
could not see it by construction.

Consequences, all applied:

* bottom columns 19–24 excluded from self-upset targets (`selfupset.tcl`) and
  columns 19–24 from campaign vectors (`gen_vectors.py`);
* the self-upset campaign re-run on the remaining scrubber columns
  (`selfupset_S2G64_noAXIcols_300.log`): **zero DAP wedges in 300 trials**;
  essential bits corrected 253/286 (88 %), DEAD 6, BLIND 5 → fatal **3.8 %**
  against 6.5 % with those columns in. About a third of what §16–17 counted
  as fatal hits on the scrubber's fabric was the test corrupting the bus.
  (Caveat: this run used the ILA build, whose placement differs from the
  essential-bit map; the control arm's one BLIND is that.)
* the readback path is only trustworthy on static frames; a dynamic-frame
  census must *vary* the access history between reads, not repeat it.

The §16.1 self-upset numbers are therefore: healed ~88 %, fatal ~4 % of
essential-bit hits on the scrubber's own fabric.

## 19. Night run 2026-09-04 — three builds, unattended, and what the prod shortfall really was

Driver `vivado/night.sh` (23:54–04:34) ran the ten steps of `night_steps.txt`
on three bitstreams built from the same RTL — `test` (TEST_MODE_G on, S2G64),
`prod` (TEST_MODE_G off) and `s4g64` — then seven follow-up queues
(05:05–11:40) chosen from the results. Logs: `campaign/2026-09-04_night/`,
running notes with every decision: `GUIDE_NOTES.md` there.

### 19.1 Campaigns (150 reachable vectors, `campaign_v2`; `v3` = v2 + re-program after a failed vector)

| run | build | n | detected | exact restore | PASS | hw corr. latency µs med / max |
|---|---|---|---|---|---|---|
| 02 | test | 150 | 148 | 150 | 148 | 60 / 88 |
| 03, 03b | prod (v2) | 150 ×2 | 124, 124 | 149, 149 | **123, 123** | 60 / 88 |
| 03d | prod, list minus the 2 loop bits | 148 | 146 | 148 | 146 | 60 / 88 |
| 19, 19b | prod (v3) | 150 ×2 | 148, 148 | 148, 149 | **146, 147** | 60 / 88 |
| 08 | s4g64 | 60 | 59 | 60 | 59 | 60 / 80 |
| 15 (+15b tail) | s4g64 (v2) | 150 (+20) | 127 (+20) | 129 (+19) | 127 (+19) | 60 / 88 |
| 20, 20b | s4g64 (v3) | 150 ×2 | 147, 147 | 149, 149 | **147, 147** | 64 / 80 |

Two vectors fail identically in every build and every run — `0x40111B w33
b27` and `0x001308 w50 b18` (11 of 11 trials): `landcheck.tcl` shows they
**never land** (readback unchanged, 2/2 each, neighbours land). They are
injector-side non-landers, not misses; the honest ceiling of this list is
148/150.

**The prod verdict.** 03's 123 is not 27 independent misses. Two failures are
the non-landers; idx 126 `0x401405 w66 b3` is detected with `rehits=36` and
`exact=0`; and *every* vector after it (127–150) is `det=0` with a stale,
unsaturated `hw_det_us` — the scrubber was no longer looking. `loop401405.tcl`
(11): after that one bit the whole-frame readback is garbage (every word
≈`0xFFFFFFDB`), the FAR register reads nonsense, the scrubber re-captures
36 times per 800 ms indefinitely, control injections go unseen, and a soft
reset (CTRL 1/7/1) does not clear it — only re-programming does. Neighbouring
bits/words/frames are clean. The same bit on the test build: `rehits=1`,
clean. Fresh-board re-tests: loop in 6 of 6 (03, 03b, 03c, 11, 19, 19b).
A second prod loop bit sits in `0x40150E w41 b5` (13, 16, 19: 4 loops in
5 trials; `w65 b3`, `w20 b3` of the same frame and `w41 b5` of `0x40150F`
and `0x40158E` loop too; after a soft reset in that state `init=0` and frames
read back massively rewritten, so the loop is not benign). With the board
re-programmed after each failed vector (`campaign_v3.tcl`, column `reprog`)
prod scores **146–147/150: the two non-landers plus one or two self-upset
bits, nothing else** — the same detection and correction as the test build,
same 60 µs median correction latency.

**Where the bits are.** Bitstreams rebuilt without the board
(`map_build.sh`) are byte-identical to the night ones apart from the header
timestamp, so their `.ll`/`.ebd` apply. `0x401405` is bottom row 0, CLB
column 40, minor 5 (an interconnect frame); the flip-flop bits of that column
belong only to `scrubber/{algorithm, syndr_handler, par_calculator,
calc_par_mem, golden_par_mem, icap_ctrl}`. `0x40150E/0F` = column 42 (no FF
bits: an interconnect-only column), `0x40158E` = column 43 (golden_par_mem,
syndr_handler, icap_ctrl). The prod build places the scrubber entirely in the
bottom half (columns 19–51). These are routing upsets in the scrubber's own
readback/parity path — the §16 "self-upset" class, hit by the plain campaign
list because two of its 150 vectors happen to fall there. Vivado's `.ebd`
marks `0x40158E w41 b5` essential and, oddly, `0x401405 w66 b3`
*non-essential* (either the essential-bit mask misses config-interface routing
or the offset arithmetic for that column is off; open).

In campaign context on a fresh prod board (13, 16, 19, 19b, and 25a–e =
`campaign_v3` vectors 140–150 ×5) `0x40150E w41 b5` looped 8 of 10 times
(rehits 34–36, the bit stays set); in 25a–e the other ten vectors passed
every time (50/50).

**s4g64** has its own pair: `0x400D16 w34 b11` (column 26: algorithm, AXI
`auto_pc`, injector) **freezes** the scrubber — `hto=1`, counters stale, every
later vector unseen — deterministically (17a/b/c, 20, 20b: 5/5; passes on
prod and test), and `0x001508 w24 b13` (top column 42) loops stochastically
(3 of 8 campaign trials; 11 of 63 fatal under the supervisor, see 19.2). With
re-programming after a failure s4g64 is 147/150 twice.

**The test build is not exempt.** The soak (19.4) alarms only in the
40-injection windows that contain list vectors 91–100; `sup_known.tcl` on
each of the ten: nine are alive 27/27, **`0x40150E w44 b11` (vector 93) goes
BLIND 36 of 68 times** and loops in the campaign 3 of 6 (23a–f). Frame
`0x40150E` — bottom column 42, minor 14 — is therefore a self-upset hot spot
in all three placements, and 02's 148/150 passed vector 93 on a coin toss.

### 19.2 Supervisor (`selfupset_sup.tcl`: heartbeat 60 ms + canary 300 ms, then re-program)

| run | build | targets | alive | DEAD | BLIND | fatal | alarm ms med (DEAD / BLIND) | recovery ms med / max |
|---|---|---|---|---|---|---|---|---|
| 05 | test | test map | 189 | 9 | 2 | 5.5 % | 1602 (1603 / 1185) | 4335 / 4363 |
| 05b | test | test map | 195 | 3 | 2 | 2.5 % | 1169 (66 / 2264) | 4316 / 4343 |
| 05c | prod | prod map | 176 | 15 | 9 | 11.9 % | 817 (66 / 1184) | 4317 / 4345 |
| 05d | s4g64 | s4g64 map | 186 | 9 | 5 | 7.0 % | 807 (450 / 1182) | 4312 / 4349 |

(201 trials each; medians are Python medians of the non-alive trials; the
log's own `SUPERVISED` line uses the upper median. No `recover_ms < 0`
anywhere: every alarm was followed by a successful re-program in ≈4.3 s.)
Test 402 trials: fatal 4.0 % — consistent with §18.6's 3.8 %. Prod's 11.9 %
is on a different target list (its own essential-bit map, scrubber
concentrated in the bottom half, so its "scrubber columns" are purer) and is
not directly comparable; it is the number to use for the prod build.

Directed (`sup_known.tcl`, fresh board per trial; first pass 08:52–09:24,
extended 11:31–11:51 to ≥ 20 trials per bit and 11:57–12:20 to ≥ 60 for the
stochastic ones; table = `vivado/sup_known_merge.py` over all `*sup_known*.log`):

| build | bit | trials | alive | DEAD | BLIND | fatal | alarm ms med / max | recovery ms med / max |
|---|---|---|---|---|---|---|---|---|
| prod | `0x401405 w66 b3` | 23 | 0 | 0 | 23 | 100 % | 1196 / 1217 | 4348 / 4500 |
| prod | `0x40150E w41 b5` | 63 | 21 | 0 | 42 | 67 % | 1184 / 4407 | 4325 / 4557 |
| prod | `0x40158E w41 b5` | 63 | 18 | 0 | 45 | 71 % | 1184 / 4566 | 4248 / 4840 |
| s4g64 | `0x400D16 w34 b11` | 23 | 0 | 23 | 0 | 100 % | 66 / 73 | 4341 / 4482 |
| s4g64 | `0x001508 w24 b13` | 63 | 52 | 6 | 5 | 17 % | 3340 / 4469 | 4319 / 4365 |
| test | `0x40150E w44 b11` | 68 | 32 | 0 | 36 | 53 % | 1180 / 1293 | 4326 / 4566 |

(first pass 3–8 trials, +20 from 24/24b/24c/26/26b, +40 from 27/27b/27c.)
`0x401405` and `0x400D16` are deterministic (23/23 each, not extended); the
column-42/43 prod bits are stochastic at ≈ 65–70 % (the 40-trial extension
gave 25/40 and 30/40, consistent with the earlier 17/23 and 15/23), the
test-build vector 93 at ≈ 50 % (20/40 new, 16/28 before); s4g64 `0x001508`
is not benign — 11/63 fatal (6 DEAD, 5 BLIND), i.e. the same bit can freeze
or loop, and its alarms come late (median 3.3 s: the canary passes a few
cycles before the fault sets in). A few prod BLIND alarms are late for the
same reason (3.4–4.6 s). **Every self-upset mode found tonight is caught by
the supervisor layer and recovered by re-programming** (no failed recovery
in 303 directed trials);
the 1.2 s BLIND latency is the canary period, the 66 ms DEAD latency the
heartbeat window.

### 19.3 Beam replay

| run | build | S | events | corrected | predicted uncorrectable | disagreements | failures |
|---|---|---|---|---|---|---|---|
| 06 (events 301–655) | test | 2 | 355 | 354 | 23 | 24 | `CERN_405_f4_b4_p1` |
| 07 | s4g64 | 4 | 300 | 300 | 12 | 12 | none |

All disagreements but one are the model predicting "uncorrectable" for an
event the silicon corrected (the model stays conservative); the one real
failure, `CERN_405_f4_b4_p1`, was corrected 3/3 on re-run (14a/b/c) — a
one-off, not a hole. Replay needs HOLD and therefore the test build.

### 19.4 Soak (plain injections cycling the 150-vector list, canary every 40)

| run | build | min | injections | canary alarms | "misses" | JTAG hard recoveries |
|---|---|---|---|---|---|---|
| 09 | test | 119 | 15280 | 46 | 1225 (8.0 %) | 2 |
| 09b | test | 60 | 7560 | 26 | 650 (8.6 %) | 0 |
| 09c | prod | 60 | 4049 | 34 | 737 (18.2 %) | 1 |
| 09d | s4g64 | 60 | 4831 | 45 | 714 (14.8 %) | 0 |

The "misses" are entirely the blind stretch between a self-upset and the
next canary (≈16–27 per alarm), and the alarms sit only in the 40-injection
windows that contain the known bits: test — vector 93 (46 alarms in 102
passes ≈ the 50 % per-trial rate measured directly); prod — idx 126
(`0x401405`, every pass) and 146 (`0x40150E`, about a quarter of passes);
s4g64 — idx 130 (`0x400D16`, every pass) and 141 (`0x001508`, stochastic).
No other vector of the list ever raised the canary in 4 h 39 min of soak
across the three builds. The soak is a supervisor test, not a detection
test; the supervisor recovered every episode (0–2 JTAG hard recoveries per
hour are the debug link, not the design).

### 19.5 Other items

* **cern0 ILA hunt (10, 10b): 0 captures in 50 iterations**, and
  `insert_ila13.tcl` lost 7 of the wanted probes (`sh_busy`, `fifo_empty`,
  `start_error_correction`, `error_correction_done`, `alg_icap_req_i`,
  `alg_dbg*`, `skip_active` — optimised away), so even a capture would not
  have shown the handler state. Still open; needs `mark_debug` on those
  signals before the next ILA build.
* **`0x00091B` (04):** w12/w40 bits never land (`landed=NO`, `first_ms=-1`),
  as do `0x00091A`/`0x00091C`; `0x000918 w12` is seen at 8 ms but reads back
  unchanged. Recorded as a frame the attribution misses (column 18 is the
  start column) — nothing to chase in the scrubber.
* **Silent mis-correction candidate** (03 idx 126, `det=1 exact=0`) was the
  `0x401405` loop, not a mis-correction: under the loop the "readback" is the
  garbage stream, so `exact` cannot be evaluated.
* **0x40150E w41 b5 in 03c** (3× re-test) gave det 0/0, 0/1, 1/1 — the
  first sign that the loop bits are stochastic in prod as well.

### 19.6 What changed / what is still open

Changed (scripts only, no RTL): `campaign_v3.tcl` (re-program after a
failed vector, `START` argument, `reprog` column); `campaign_v2s.tcl`
(`START`); `loop401405.tcl`, `landcheck.tcl`, `sup_known.tcl`,
`campaign_freeze.tcl`/`freeze_vectors.tcl`, `campaign_noself.tcl`/
`campaign_vectors_noself.tcl`, `map_build.sh` (offline `.ll`/`.ebd` per
build), `selfupset_sup_{prod,s4g64}.tcl` + `selfupset_targets_{prod,s4g64}.tcl.out`
(each build's own essential-bit target list), `hunt_only.sh`,
`night_ila13.{bit,ltx}`, `followup*_steps.txt` (1–10), `sup_known_merge.py`
(merges all `*sup_known*.log` into the directed table above), `night_report.py`.

Open:
1. A hit-storm self-check in RTL (e.g. more than N captures per scan ⇒ raise
   a self-fault flag) would turn the 1.2 s canary latency into milliseconds
   for the loop class; the DEAD class already alarms in 66 ms. Design
   decision, not done unattended.
2. Why `0x401405 w66 b3` is "non-essential" in the `.ebd` yet wrecks readback.
3. Frame `0x40150E` (bottom column 42) is a hot spot in all three placements —
   worth a look at what routes through that interconnect column
   (ICAP data bus?).
4. cern0 ILA: re-insert with the seven missing probes kept.
5. 05c's 11.9 % fatal on the prod list vs 4 % on the test list: placement
   or list purity? A test-build run on the prod-style column set would tell.
