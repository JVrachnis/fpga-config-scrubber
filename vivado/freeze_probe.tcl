connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
set t0 [clock milliseconds]
set last -1; set tot 0; set freeze 0
for {set i 0} {$i < 150} {incr i} {
  set s [mrd -force -value 0x43C00010]
  set c [expr {($s >> 8) & 0xFF}]
  set d [expr {($s >> 16) & 0xFF}]
  set p [expr {([mrd -force -value 0x43C00014] >> 24) & 0xFF}]
  if {$last >= 0} { incr tot [expr {($c - $last) & 0xFF}] }
  set last $c
  if {$i % 10 == 0 || ($i > 20 && (($c - $last) & 0xFF) == 0 && $freeze == 0)} {
    puts [format "t=%5d ms  cnt=%3d  cum_frames=%5d  diag=0x%02X  pcalc=0x%02X" [expr {[clock milliseconds]-$t0}] $c $tot $d $p]
  }
  after 30
}
puts [format "TOTAL frames counted: %d  (init should be ~5153 mod tracking)" $tot]
puts [format "final diag=0x%02X pcalc=0x%02X" [expr {([mrd -force -value 0x43C00010]>>16)&0xFF}] [expr {([mrd -force -value 0x43C00014]>>24)&0xFF}]]
