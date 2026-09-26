# Is FAR bit22 = 1 (top half) systematically undetectable, or are the failing
# vectors simply not in the scrubber's valid frame map?
# 0x40110C is the positive control: it was captured at 0x40110E in the farcheck
# probe, so top-half detection is known to be possible.
connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1500
proc stat {} { return [mrd -force -value 0x43C00010] }
proc free {} { return [expr {([stat]>>4)&1}] }
proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }
proc drain {} { for {set i 0} {$i<40} {incr i} { if {[mrd -force -value 0x43C00014]&2} { cc } else { break } } }
proc wf {ms} { set t [clock milliseconds]
  while {[clock milliseconds]-$t < $ms} { if {[free]} { return 1 }; after 5 }; return 0 }
proc freeze {} { mwr -force 0x43C0000C 0x81; wf 500; mwr -force 0x43C0000C 0x881; after 30 }
proc thaw {} { mwr -force 0x43C0000C 0x1; after 120 }
proc inject {far word mask} {
  mwr -force 0x43C00000 $far; mwr -force 0x43C00004 $word; mwr -force 0x43C00008 $mask
  mwr -force 0x43C0000C 0x881; after 4
  mwr -force 0x43C0000C 0x887; after 60
  mwr -force 0x43C0000C 0x881; after 40 }
proc watch {target ms} { set t [clock milliseconds]; set n 0
  while {[clock milliseconds]-$t < $ms} {
    if {[mrd -force -value 0x43C00014]&2} {
      if {[expr {[mrd -force -value 0x43C00018]&0xFFFFFF}] == $target} { incr n }; cc }
    after 12 }
  return $n }

puts "FAR       word  r1 r2 r3   verdict"
foreach v {{0x40110C 30 0x00000400} {0x001603 32 0x40000000}
           {0x40109C 55 0x00200000} {0x4019A0 66 0x01000000}
           {0x401022 41 0x00000004} {0x400E18 54 0x01000000}
           {0x400102 61 0x00000020} {0x40110C 61 0x00000020}} {
  set F [lindex $v 0]; set W [lindex $v 1]; set M [lindex $v 2]
  set row {}; set tot 0
  for {set r 0} {$r<3} {incr r} {
    drain; freeze; inject $F $W $M; thaw
    set n [watch [expr {[expr {$F}]+2}] 2500]
    lappend row [expr {$n>0}]; incr tot [expr {$n>0}]
    after 300; drain
  }
  puts [format "%-9s %-5s %s   %d/3" $F $W [join $row " "] $tot]
}
