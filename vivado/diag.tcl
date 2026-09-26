connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
proc cnt {} { return [expr {([mrd -force -value 0x43C00010] >> 8) & 0xFF}] }
puts "counter right after config: [cnt]"
# hand PCAP -> ICAP
mwr -force 0xF8007000 0x4600E07F
puts "counter after ICAP handoff: [cnt]"
# unlock SLCR, pulse PL reset so scrubber restarts with ICAP available
mwr -force 0xF8000008 0x0000DF0D
mwr -force 0xF8000240 0x0000000F ;# assert FCLK resets
after 20
mwr -force 0xF8000240 0x00000000 ;# release
after 50
# watch the scan counter over ~1s
set a [cnt]; after 200; set b [cnt]; after 200; set c [cnt]; after 500; set d [cnt]
puts "SCAN_COUNTER after PL reset: $a -> $b -> $c -> $d"
puts "STATUS: [format 0x%08X [mrd -force -value 0x43C00010]]"
