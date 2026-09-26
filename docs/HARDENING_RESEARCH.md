# Parameterized 2-D geometry + scrubber self-hardening — research memo

*Branch `feature/param-2d-hardening`, 2026-08-29. Sources at end.*

## Part 1 — Parameterized frame grouping & parity size

### What the parameters mean physically
- **S = subgroups_per_group (interleave depth).** The vertical code assigns frame
  `f` to subgroup `f mod S`; each subgroup has its own parity frame. Correction
  capacity: one erroneous frame per subgroup, so up to **S simultaneously bad
  frames per group** if they land in distinct subgroups — and any run of up to
  S *adjacent frames* (inter-frame MBU clusters, seen in the beam data's
  consecutive-column patterns) is guaranteed to split across subgroups.
  Cost: parity BRAM grows linearly in S (groups × S × 101 × 32b), and the
  syndrome-matching pair search gets S independent lanes.
- **G = max_frames_per_group.** Group = correction domain + scan granularity.
  With bounded per-column passes, G's natural value is "one column" (≤43
  frames on xc7z010); larger G amortizes parity storage across more frames
  (fewer parity frames per device) at the cost of a bigger reconstruction
  domain and longer correction passes. G also sizes the syndromes memory and
  the group/frame split of the FAR.
- Design target: both fully generic, TB-validated at (G=64,S=2) [baseline],
  (G=64,S=4), (G=32,S=2). The device geometry package stays orthogonal.

### Current state (audit summary)
Most subgroup math is already `mod subgroups_per_group` and vectors are sized
by the generic. Known hard-coded assumptions to fix:
1. `parity_calculator`: first-frame-of-subgroup detection `locked_far(...) < 2`
   — must be `< subgroups_per_group`.
2. Handler single/multiple flag transition logic — verify S>2 semantics
   (flags are per-subgroup vectors; the single→multiple promotion is generic).
3. Parity memory addressing (`subgroup & word` concatenation) — widths derive
   from log2(subgroups_per_group): verify log2(1)=0 edge and non-power-of-2 S
   (restrict S to powers of two, assert in pkg).
4. TB engine: subgroup emulation in checks (frames 12&14 "same subgroup"
   selection must be computed from S, not assumed even/even).

## Part 2 — Protecting the scrubber's own logic ("who scrubs the scrubber")

The scrubber lives in the fabric it protects. Its *configuration* upsets are
self-healed by its own scanning — **provided its state survives the window
until repair**. That is the classic TMR+scrubbing synergy: TMR masks the
transient functional effect, scrubbing repairs the config before a second
upset defeats the voter. The literature-backed menu, ranked for this design:

### 1. Golden-parity BRAM: built-in SECDED ECC (highest priority)
The golden parity memory is the scrubber's only irreplaceable state: corrupt
it and the scrubber *writes corruption into the device*. BRAM content is NOT
covered by configuration scrubbing — it needs its own protection. 7-series
RAMB36E1 offers built-in Hamming SECDED (64 data + 8 parity, 512×72 SDP
mode). Plan: repack the parity frames into 64-bit ECC words (101×32b frame =
50.5 ECC words → 51 words/frame with padding), add a low-priority background
sweep port that reads (and thus corrects) every location periodically, and
surface SBITERR/DBITERR counters on the diag bus. DBITERR → declare golden
parity lost → automatic re-init sweep.

### 2. Distributed TMR with feedback voters on the critical FSMs
Plain triplication diverges after an upset unless every feedback path carries
a majority voter re-synchronizing the three domains each cycle (BYU voter-
insertion literature; persistent-error argument). With scrubbing repairing
the config, voted TMR state re-converges automatically. Practical flow here:
manual VHDL triplication of the *state and index registers* of, in
criticality order: syndromes handler (FSM + entry indices + entry_group),
scan driver FSM, parity-calculator control (locked/chain registers), EDC
state machine. Voters as small combinational functions; `DONT_TOUCH` /
`keep` attributes on the triplicated registers and voter nets so Vivado does
not optimize the redundancy away (it will otherwise). Area estimate: the
control registers are a few hundred FFs total — 3× on those plus voters is
cheap next to the 36 RAMB18.

### 3. Safe/encoded FSM states (cheap, immediate)
All FSMs get `fsm_safe_state` (Vivado attribute) or explicit others→recovery
arcs, so an upset landing in a state register cannot wedge a machine in an
unreachable state. Hamming-encoded state registers (auto-correcting) are the
stronger variant with heavy-ion evidence of ~2 orders cross-section
reduction; apply to the handler FSM first.

### 4. Watchdog + self-recovery (system-level backstop)
The scan-activity counter is already a heartbeat. Add a fabric watchdog (or
PS-side monitor) that on heartbeat stall issues a scrubber soft reset and —
if golden parity integrity is in doubt (DBITERR) — a golden re-init. This
converts any residual wedge class into a bounded outage.

### 5. Explicitly out of scope (for now)
Full-design TMR via external tools (Synopsys Synplify TMR flows / legacy
Xilinx TMRTool) — heavyweight, tool-dependent; our partial, criticality-
ranked TMR aligns with the dependability-modeling literature showing
partitioned/selective TMR captures most of the benefit at a fraction of the
area.

## Proposed implementation order (branch)
1. Parameter audit fixes + `S`/`G` generic cleanliness; TB matrix
   (S=2 regression, S=4, G=32). Assert power-of-2 S.
2. `fsm_safe_state` + recovery arcs everywhere (one build, near-zero cost).
3. Golden/calc parity BRAM ECC repack + background sweep + DBITERR policy.
4. Manual TMR of handler FSM + indices with feedback voters (DONT_TOUCH),
   then scan driver; measure area/timing at each step.
5. Fault-injection *into the scrubber itself* in the closed-loop TB
   (flip TMR'd state mid-operation; flip a golden-parity word) to demonstrate
   the mitigation experimentally — the same live-verification standard as the
   main campaign.

## Sources
- TMR survey: https://arxiv.org/html/2603.14411v1
- Voter insertion for FPGA TMR (BYU/LANL): https://dl.acm.org/doi/10.1145/1723112.1723154 ,
  https://www.nsf-shrec.org/sites/default/files/2024-03/FPGA10_B3.pdf ,
  https://scholarsarchive.byu.edu/cgi/viewcontent.cgi?httpsredir=1&article=3067&context=etd
- TMR partitioning dependability modeling: https://www.sciencedirect.com/science/article/abs/pii/S0951832018304034
- Self-reference scrubber for TMR systems: https://link.springer.com/chapter/10.1007/978-3-642-24154-3_14
- 7-series BRAM ECC (UG473): https://cse.usf.edu/~haozheng/teach/cda4253/doc/ug473_7Series_Memory_Resources.pdf
- BRAM ECC practice: https://medium.com/@aptaylorceng/microzed-chronicles-error-correction-and-bram-34eb8b62528d
- FSM fault-tolerant coding: https://www.techbriefs.com/component/content/article/2620-npo-41050
- Erasure/interleaved codes for config MBUs: https://dl.acm.org/doi/10.1145/2593069.2593191 ,
  https://dl.acm.org/doi/10.1109/TVLSI.2015.2425653
- ESA TMR VHDL attribute practice: https://microelectronics.esa.int/techno/fpga_003_01-0-2.pdf
- Vivado DONT_TOUCH / logic preservation: https://docs.amd.com/r/2022.2-English/ug912-vivado-properties/DONT_TOUCH
- Xilinx TMR approach (minority voters on outputs): https://medium.com/@aptaylorceng/microzed-chronicles-triple-modular-redundancy-and-microblaze-78080b8046e4

---
## Status update (2026-08-29)

**Parameterization: VALIDATED.** Closed-loop TB config matrix, all checks passing:

| S (subgroups) | G (max frames/group) | Result | Notes |
|---|---|---|---|
| 2 | 64  | PASS | baseline (master-equivalent) |
| 4 | 64  | PASS | four adjacent frames (20..23) corrected simultaneously |
| 4 | 128 | PASS | column-aligned groups (G ≥ 43 minors ⇒ group ≡ column) |

Hardcodes found & fixed during the audit (each one a silent G/S=64/2 assumption):
1. `parity_calculator.vhd` — subgroup parity-accumulator init used `< 2` instead of
   `< subgroups_per_group`.
2. `syndrome_handler.vhd` — group-base reconstruction padded with a literal `"000000"`
   (= log2(64) zeros) at two sites; now `(log2(max_frames_per_group)-1 downto 0 => '0')`.
   This was the G=128 elaboration bound-check failure.

**Hardening step 1 (safe-state FSMs): DONE.** `fsm_safe_state = "reset_state"` synthesis
attribute applied to all six FSMs: parity_calculator, syndrome_handler,
algorithm_state_machine, algorithm_icap_if, icap_controller, and the scan driver
(`scan_state` in scrubber_ip). GHDL ignores the attribute (sim unaffected); Vivado adds
illegal-state recovery logic. Resource/timing cost to be measured at next silicon build.

Next per implementation order: step 2 — golden/calc parity BRAM SECDED (RAMB36E1 512×72)
+ background sweep + DBITERR policy; then step 3 — manual TMR of handler indices.
