connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
ps7_init
ps7_post_config
puts "STATUS(0x43C00010): [format 0x%08X [mrd -force -value 0x43C00010]]"
puts "FECC_FLAGS(0x43C00014): [format 0x%08X [mrd -force -value 0x43C00014]]"
puts "FECC_FAR(0x43C00018): [format 0x%08X [mrd -force -value 0x43C00018]]"
puts "FECC_SYN(0x43C0001C): [format 0x%08X [mrd -force -value 0x43C0001C]]"
