connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
ps7_init; ps7_post_config
# write injection-parameter registers (pure input latches, no ICAP action)
mwr -force 0x43C00000 0x00ABCDEF ;# Far_address
mwr -force 0x43C00004 0x00000055 ;# Word_pos
mwr -force 0x43C00008 0xDEADBEEF ;# Fault_Word mask
puts "FAR_rb (0x00): [format 0x%08X [mrd -force -value 0x43C00000]]"
puts "WPOS_rb (0x04): [format 0x%08X [mrd -force -value 0x43C00004]]"
puts "MASK_rb (0x08): [format 0x%08X [mrd -force -value 0x43C00008]]"
