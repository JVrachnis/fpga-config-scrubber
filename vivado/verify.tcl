connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc capf {} { return [expr {[mrd -force -value 0x43C00014]&7}] }
proc far {} { return [mrd -force -value 0x43C00018] }
proc clearcap {} { mwr -force 0x43C0000C 0x10; after 3; mwr -force 0x43C0000C 0x0 }
# prime init
mwr -force 0x43C00008 0x0; mwr -force 0x43C0000C 0x1; after 5; mwr -force 0x43C0000C 0x7; after 40; mwr -force 0x43C0000C 0x1
after 500
clearcap; after 300
puts [format "baseline (scanner running, no injected fault): cap=0x%X FAR=0x%08X" [capf] [far]]
# inject a single-bit fault; do NOT re-read - let the autonomous scan find it
mwr -force 0x43C00000 0x00002000; mwr -force 0x43C00004 0x0A; mwr -force 0x43C00008 0x1
mwr -force 0x43C0000C 0x1; after 5; mwr -force 0x43C0000C 0x7; after 40; mwr -force 0x43C0000C 0x1
after 300
puts [format "after inject (autonomous detect?): cap=0x%X FAR=0x%08X" [capf] [far]]
# clear latch, wait several scan passes, see if it RE-detects (persist) or stays clean (corrected)
clearcap; after 1000
puts [format "cleared +1s: cap=0x%X FAR=0x%08X" [capf] [far]]
clearcap; after 2000
puts [format "cleared +2s: cap=0x%X FAR=0x%08X" [capf] [far]]
