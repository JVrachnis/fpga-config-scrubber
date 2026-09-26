connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
after 3000
# last-minor frames vs mid-column frames, frozen op then plain verify, 6 reps each
foreach F {0x400A23 0x400BA3 0x000A23 0x001623 0x400988 0x000A08 0x400A20 0x000A22} {
  set col [expr {($F>>7)&0x3FF}]; set minor [expr {$F&0x7F}]
  set b0 [readframe $F]; set bad 0
  for {set r 0} {$r<6} {incr r} {
    freeze; readframe $F 0x881; thaw; after 100
    set v [readframe $F]
    if {[llength [framediff $b0 $v]]} { incr bad; board_up; after 2000; set b0 [readframe $F] }
  }
  puts [format "%-9s col=%-2d minor=%-2d  frozen-op corruptions: %d / 6" $F $col $minor $bad]
}
