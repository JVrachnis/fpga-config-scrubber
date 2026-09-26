# 2019 prototypes (J. Vrachnis)

These are the first ICAPE2 experiments on a live xc7z010 (Nov to Dec 2019), before the
SYSYFOS IP tree existed. They come from John's own Vivado projects of that period. The files
have no author headers. They are kept as history: they show where the reverse-engineered ICAP
protocol handling in `rtl/modules/icap_controller/icap_controller.vhd` started.

| Path | What |
|---|---|
| `2019_icap/ICAP_COM.vhd` | First ICAPE2 command sequencer: sync, configuration-register read, frame readback |
| `2019_icap/icape_common.vhd`, `icape_com_producers.vhd` | Command-word constants and packet-producing procedures. The fault-injection IP below uses the same two files. |
| `2019_fault_injection_ip/ICAP_Fault_Injection.vhd` | Read-modify-write fault injector: read a frame, XOR a mask into one word, write it back |
| `2019_fault_injection_ip/Fault_injection_AXI.vhd` | AXI-side glue for the injector |
| `2019_fault_injection_ip/Fault_Injection_v1_0*.vhd` | Vivado "Create and Package IP" AXI4-Lite peripheral template (tool-generated boilerplate, with user logic added) |
| `2019_ps_driver/main.c` | Four register writes that fire one injection from the ARM: FAR, word, mask, go (`0x43C00000` to `0x43C0000C`) |

The register map (FAR / word / mask / control at `0x43C0_0000`) survives in the 2021 to 2026
injector.

**Not included:** `dual_port_mem.vhd`, which `ICAP_Fault_Injection.vhd` instantiates. It has
the same interface as the TELETEL `dualportmem` (A. Tavoularis) and appears to be derived from
it. Any simple dual-port RAM with the ports `clk, wr_en, wr_addr, data_in, rd_en, rd_addr,
data_out` can stand in for it.
