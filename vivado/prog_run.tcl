connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1500
set st [mrd -force -value 0x43C00010]
puts [format "RUNNING: init=%d scan=%d" [expr {($st>>16)&1}] [expr {($st>>8)&0xFF}]]
after 300
puts [format "scan now=%d (must differ)" [expr {([mrd -force -value 0x43C00010]>>8)&0xFF}]]
