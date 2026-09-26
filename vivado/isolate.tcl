connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc st {} { return [mrd -force -value 0x43C00010] }
proc cnt {} { return [expr {([st] >> 8) & 0xFF}] }
puts "counter before injector: [cnt]"
# run injector sync+inject (proven to work pre-rebuild)
mwr -force 0x43C00000 0x00000920
mwr -force 0x43C00004 0x0000000A
mwr -force 0x43C00008 0x00000001
mwr -force 0x43C0000C 0x1 ; after 5
mwr -force 0x43C0000C 0x7 ; after 30
set synced [expr {[st] & 1}]
mwr -force 0x43C0000C 0x1
puts "INJECTOR synced bit: $synced   (1 = injector reached ICAP sync)"
puts "counter after injector ICAP activity: [cnt]"
puts "cap_flags 0x14: [format 0x%08X [mrd -force -value 0x43C00014]]"
puts "cap_FAR   0x18: [format 0x%08X [mrd -force -value 0x43C00018]]"
puts "cap_SYN   0x1C: [format 0x%08X [mrd -force -value 0x43C0001C]]"
puts "STATUS: [format 0x%08X [st]]"
