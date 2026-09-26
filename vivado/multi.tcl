# Plant N upsets with one hand-off per upset, holding correction throughout:
#   freeze -> inject -> thaw INTO HOLD -> freeze (hold kept) -> inject -> ...
# then release HOLD and watch the scrubber deal with all of them at once.
# This is the method the concurrency-capacity experiments need, given that
# the injector lands exactly one upset per grant (pair.tcl).
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up

proc freeze_held {} {
  ctrl 0xC1                               ;# TEST_FREEZE + HOLD
  if {![wait_free 500]} { puts "HANDOFF FAILED"; ctrl 0x41; return 0 }
  ctrl 0x8C1; after 20; return 1 }

proc plant_set {frames} {
  drain
  ctrl 0x41; after 50                     ;# hold from the start
  set w 20
  foreach F $frames {
    if {![freeze_held]} { return 0 }
    inject 0x8C1 $F $w 0x8; incr w 7
    ctrl 0x41; after 60                   ;# thaw into hold
  }
  return 1 }

foreach N {2 3 8} {
  set all {0x000A14 0x400B09 0x001919 0x000C08 0x001606 0x001304 0x400D12 0x401220}
  set set_ [lrange $all 0 [expr {$N-1}]]
  set d0 [initdrops]; set w0 [wdpar]
  plant_set $set_
  # all N should now be visible while held
  set seen [collect 1500]
  set held 0; foreach F $set_ { if {[lsearch -exact $seen [expr {$F+2}]] >= 0} { incr held } }
  # release and see what survives 1.5 s of free scrubbing
  ctrl 0x1; after 1500
  set left [collect 1500]
  set dirty 0; foreach F $set_ { if {[lsearch -exact $left [expr {$F+2}]] >= 0} { incr dirty } }
  foreach F $set_ { if {[lsearch -exact $left [expr {$F+2}]] >= 0} { puts "   dirty: $F" } }
  puts [format "N=%d  planted+seen while held: %d/%d   still dirty after release: %d   drops+%d wd_flip=%d init=%d" \
        $N $held $N $dirty [expr {([initdrops]-$d0)&3}] [expr {[wdpar]!=$w0}] [init]]
  # cleanup: re-inject anything still dirty
  foreach F $set_ { if {[lsearch -exact $left [expr {$F+2}]] >= 0} { inject 0x1 $F 20 0x8; after 100 } }
  after 500; drain
}
puts "final: [recword]"
