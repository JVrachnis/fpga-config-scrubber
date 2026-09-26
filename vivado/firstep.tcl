connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1200
proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }
proc shot {fr tag} {
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 10; mwr -force 0x43C00008 0x8
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
  set t0 [clock milliseconds]; set n 0
  while {[clock milliseconds]-$t0 < 800} { cc; after 25
    if {[expr {[mrd -force -value 0x43C00014]&2}]} {
      if {[expr {[mrd -force -value 0x43C00018]&0xFFFFFF}] == $fr+2} { incr n } } }
  set st [expr {$n>5 ? "STUCK" : "ok"}]
  puts [format "  %-28s 0x%06X : %s" $tag $fr $st]
  if {$n>5} { mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 10; mwr -force 0x43C00008 0x8
    mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1; after 500 }
}
puts "SAME FRAME, repeated - first-episode hypothesis:"
shot 0x0C00 "attempt 1 (first ever)"
shot 0x0C00 "attempt 2 (same frame)"
shot 0x0C00 "attempt 3 (same frame)"
shot 0x1200 "attempt 4 (other frame)"
shot 0x0C00 "attempt 5 (back to first)"
