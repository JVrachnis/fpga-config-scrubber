connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc st {} { return [mrd -force -value 0x43C00010] }
# run injector (proves reset released + clock + ICAP usable)
mwr -force 0x43C00000 0x00000920; mwr -force 0x43C00004 0x0A; mwr -force 0x43C00008 0x1
mwr -force 0x43C0000C 0x1; after 5; mwr -force 0x43C0000C 0x7; after 30; mwr -force 0x43C0000C 0x1
set s [st]
puts [format "STATUS=0x%08X" $s]
puts "  injector synced (bit0)     : [expr {$s & 1}]"
puts "  scan_counter (bits15:8)    : [expr {($s>>8)&0xFF}]"
puts "  scrub_diag   (bits23:16)   : [format 0x%02X [expr {($s>>16)&0xFF}]]"
