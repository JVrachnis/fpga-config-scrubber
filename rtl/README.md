# RTL: what is here and what is not

The scrubber is a joint design. This directory contains the VHDL written by John Vrachnis;
each such file carries his copyright and an MIT SPDX line. The rest of the IP core was written by
other members of the SYSYFOS project at the University of Piraeus (and one TELETEL block) and is
**not** included, because those authors have not licensed it for redistribution. They are described below so that the included
files and the benches still make sense.

## Included

| File | Author | Notes |
|---|---|---|
| `modules/icap_controller/icap_controller.vhd` | J. Vrachnis (2020; extended 2026) | ICAPE2 master: sync/desync, type-1/type-2 packets, FDRO frame readback with the dummy frame, FDRI write-back, bit-swapped data path. The protocol was reverse-engineered on silicon with an ILA (Nov 2019 to Aug 2021). The 2026 changes add safe-state FSM encoding and the timing fixes. |
| `modules/mem_blocks/pchk_dualportmem.vhd` | J. Vrachnis (2026) | Golden-parity store with per-byte parity (36-bit words, exactly RAMB18 width), detect-only, plus a simulation-only upset hook for the closed-loop bench. It is a drop-in replacement for the inherited `dualportmem`, so it keeps the same port names. |
| `v1.8/device_geometry_pkg.vhd` | J. Vrachnis (2026) | Measured xc7z010 column geometry (minor counts per column, per half) and the ILA-measured frame-attribution identity (`FAR_d - 1`, with the column-boundary case). |
| `v1.8/icape_common.vhd` | J. Vrachnis (2019 to 2021, see note) | ICAP command constants and FAR helpers. It has no author header. It descends from John's 2019 ICAP prototype (`prototypes/2019_icap/icape_common.vhd`) and is attributed on that basis. |
| `modules/parity_calculator/parity_calculator.vhd` (+ tb) | J. Vrachnis (2020; extended 2026) | Parity sweep and compare pass. 2026: pass-end flag sticky until consumed, bounded scan passes (ends the overrun into invalid FAR space), frame-attribution fix, safe-state FSMs. |
| `modules/syndrome_handler/syndrome_handler.vhd` (+ tb) | J. Vrachnis (2020; extended 2026) | Reactive master FSM that stores per-group Frame-ECC syndromes. 2026: TMR with feedback voters on `initialized` and on the two syndrome-memory indices, syndrome-memory index desync fix, golden-parity-error handling. |
| `modules/fault_injection/fault_Injection.vhd`, `fault_Injection_axi_interface.vhd` | J. Vrachnis (2021; extended 2026) | AXI4-Lite fault injector and register file at `0x43C0_0000`; descends from the 2019 injector prototype. 2026: observability registers (Frame-ECC sticky capture, scan counter, diagnostics), request-first injection, injector FAR guard, frame readback (Rev. 1.14). |
| `v1.8/scrubber_wrapper.vhd` | J. Vrachnis (2021; extended 2026) | AXI top that ties the injector to the scrubber core. |

## Not included (inherited, described only)

| Block | Original author | Role | What changed in 2026 (J. Vrachnis) |
|---|---|---|---|
| `scrubber_ip.vhd`, `scrubber_ip_pkg.vhd`, `scrubber_ip_wrapper.vhd` | V. Vlagkoulis | Top level, constants, and the (S, G) geometry generics | Continuous-scan driver (geometry-aware, about 6 ms per sweep), progress watchdog that preserves the golden store across its reset, mark-and-skip for beyond-capacity groups, `TEST_MODE_G` instrumentation (hold, freeze, clock freeze, ordered hand-off), diagnostics and a live core-state word |
| `icap_arbiter.vhd` | V. Vlagkoulis | Rotating-priority arbiter: scan/parity, EDC correction, injector, spare | Safe-state FSM |
| `edc_algorithm.vhd`, `algorithm_state_machine.vhd`, `algorithm_icap_if.vhd`, `calc_mem_read_arbiter.vhd` | V. Vlagkoulis | The 2-D corrector: per-group decision tree over Frame-ECC syndromes and the calculated-parity frames, correction FIFO, read, merge and write-back | Dedicated merge state (removes a cross-module phase assumption), start-handshake deadlock fix, accept-then-wait completion race fix, safe-state FSMs |
| `golden_parity_mem.vhd`, `calc_parity_mem.vhd`, `fwft_fifo.vhd`, `log2_pkg.vhd` | V. Vlagkoulis | Golden and calculated parity stores, FIFOs, helper package | Golden store switched to `pchk_dualportmem`, regenerate-on-parity-error; no LUTRAM or SRL anywhere in the core |
| `dualportmem.vhd` | A. Tavoularis (TELETEL 2010 to 2015) | Generic dual-port RAM | Forced to block RAM (`ram_style = "block"`) |

## Building

`sim/core_tb/build.sh` and `sim/injector_tb/build.sh` list every file they analyse. To run
them, place the inherited sources at those paths. The Vivado scripts in `vivado/` assume the
original project layout and a `SCRUBBER_ROOT` environment variable that points at the
repository root. They are kept as the exact recipes behind the reported results. Without the
inherited RTL they do not reproduce a build.
