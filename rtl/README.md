# RTL: what is here and what is not

The scrubber is a joint design. This directory contains only the VHDL whose authorship by
John Vrachnis is recorded in the source headers or in the project history. The rest of the IP
core belongs to the SYSYFOS project at the University of Piraeus. Those files carry
"Copyright University of Piraeus 2020" (or TELETEL) headers and no licence that allows
redistribution, so they are **not** included. They are described below so that the included
files and the benches still make sense.

## Included

| File | Author | Notes |
|---|---|---|
| `modules/icap_controller/icap_controller.vhd` | J. Vrachnis (2020; extended 2026) | ICAPE2 master: sync/desync, type-1/type-2 packets, FDRO frame readback with the dummy frame, FDRI write-back, bit-swapped data path. The protocol was reverse-engineered on silicon with an ILA (Nov 2019 to Aug 2021). The 2026 changes add safe-state FSM encoding and the timing fixes. **The header carries the original project notice "Copyright University of Piraeus 2020"; see the note in the top-level `LICENSE`.** |
| `modules/mem_blocks/pchk_dualportmem.vhd` | J. Vrachnis (2026) | Golden-parity store with per-byte parity (36-bit words, exactly RAMB18 width), detect-only, plus a simulation-only upset hook for the closed-loop bench. It is a drop-in replacement for the inherited `dualportmem`, so it keeps the same port names. |
| `v1.8/device_geometry_pkg.vhd` | J. Vrachnis (2026) | Measured xc7z010 column geometry (minor counts per column, per half) and the ILA-measured frame-attribution identity (`FAR_d - 1`, with the column-boundary case). |
| `v1.8/icape_common.vhd` | J. Vrachnis (2019 to 2021, see note) | ICAP command constants and FAR helpers. It has no author header. It descends from John's 2019 ICAP prototype (`prototypes/2019_icap/icape_common.vhd`) and is attributed on that basis. |

## Not included (inherited, described only)

| Block | Original author | Role | What changed in 2026 (J. Vrachnis) |
|---|---|---|---|
| `scrubber_ip.vhd`, `scrubber_ip_pkg.vhd`, `scrubber_ip_wrapper.vhd` | V. Vlagkoulis | Top level, constants, and the (S, G) geometry generics | Continuous-scan driver (geometry-aware, about 6 ms per sweep), progress watchdog that preserves the golden store across its reset, mark-and-skip for beyond-capacity groups, `TEST_MODE_G` instrumentation (hold, freeze, clock freeze, ordered hand-off), diagnostics and a live core-state word |
| `icap_arbiter.vhd` | V. Vlagkoulis | Rotating-priority arbiter: scan/parity, EDC correction, injector, spare | Safe-state FSM |
| `edc_algorithm.vhd`, `algorithm_state_machine.vhd`, `algorithm_icap_if.vhd`, `calc_mem_read_arbiter.vhd` | V. Vlagkoulis | The 2-D corrector: per-group decision tree over Frame-ECC syndromes and the calculated-parity frames, correction FIFO, read, merge and write-back | Dedicated merge state (removes a cross-module phase assumption), start-handshake deadlock fix, accept-then-wait completion race fix, safe-state FSMs |
| `golden_parity_mem.vhd`, `calc_parity_mem.vhd`, `fwft_fifo.vhd`, `log2_pkg.vhd` | V. Vlagkoulis | Golden and calculated parity stores, FIFOs, helper package | Golden store switched to `pchk_dualportmem`, regenerate-on-parity-error; no LUTRAM or SRL anywhere in the core |
| `dualportmem.vhd` | A. Tavoularis (TELETEL 2010 to 2015) | Generic dual-port RAM | Forced to block RAM (`ram_style = "block"`) |
| `parity_calculator.vhd`, `syndrome_handler.vhd` | **Unrecorded** (Sep 2020, no author header) | Parity sweep and compare pass; reactive master FSM that stores per-group syndromes | Pass-end flag made sticky until consumed and bounded scan passes (ends the overrun into invalid FAR space), TMR with feedback voters on `initialized` and on the two syndrome-memory indices, syndrome-memory index desync fix, frame-attribution fix, golden-parity-error handling, safe-state FSMs |
| `fault_Injection.vhd`, `fault_Injection_axi_interface.vhd`, `scrubber_wrapper.vhd` | **Unrecorded** (2021, no author header) | AXI4-Lite fault injector and register file at `0x43C0_0000`, AXI top | Observability registers (Frame-ECC sticky capture, scan counter, diagnostics), request-first injection, injector FAR guard, frame readback (Rev. 1.14) |

The unrecorded rows are open questions for the author. They stay out until authorship and
licensing are settled.

## Building

`sim/core_tb/build.sh` and `sim/injector_tb/build.sh` list every file they analyse. To run
them, place the inherited sources at those paths. The Vivado scripts in `vivado/` assume the
original project layout and a `SCRUBBER_ROOT` environment variable that points at the
repository root. They are kept as the exact recipes behind the reported results. Without the
inherited RTL they do not reproduce a build.
