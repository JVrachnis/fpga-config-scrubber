# What actually happens after a thaw?  (review item 2)
#
# The freeze work measured detection only, and detection after a thaw takes
# ~1-2.5 s against a 3.3 ms sweep. Candidates: golden re-init (poisoned pass),
# watchdog soft reset (2.68 s), or a hang. All three are now visible:
#   init_drops   +1 per parity_initialized 1->0    (re-init happened)
#   wd_fires     parity flips                       (watchdog reset happened)
#   time-to-first-capture at ~10 ms resolution
# and each frozen trial now also checks that the frame was CORRECTED.
#
# A: freeze/thaw with NO injection - the cost of the freeze itself
# B: freeze, inject, thaw - detection latency + recovery word + correction
# C: same as B but thaw into HOLD_CORRECTION then release - does holding
#    change the recovery path?
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up

proc rec_delta {d0 w0} { return [format "drops+%d wd_flip=%d" [expr {([initdrops]-$d0)&3}] [expr {[wdpar]!=$w0}]] }

puts "=== A. freeze / thaw, nothing planted (x5) ==="
for {set r 0} {$r<5} {incr r} {
  drain; set d0 [initdrops]; set w0 [wdpar]; set s0 [sc]
  if {![freeze]} { continue }
  after 300
  thaw
  # when does the scan counter start moving again?
  set t [clock milliseconds]; set moving -1
  while {[clock milliseconds]-$t < 3500} {
    if {[sc] != $s0} { set moving [expr {[clock milliseconds]-$t}]; break }
    after 10 }
  after 3000
  puts [format "  r%d: scan resumed at %5d ms   %s   init=%d" $r $moving [rec_delta $d0 $w0] [init]]
}

set frames {0x000A14 0x001606 0x400B09 0x001304 0x400D12 0x001919 0x000C08 0x401220}
puts ""
puts "=== B. freeze, inject, thaw (free-running) ==="
puts "far       first_ms  rehits  drops  wd   init  verdict"
foreach F $frames {
  set target [expr {$F+2}]
  drain; set d0 [initdrops]; set w0 [wdpar]
  if {![freeze]} { continue }
  inject 0x881 $F 20 0x8
  thaw
  set first [first_hit $target 3500]
  after 300
  set re [hits_in $target 800]
  set dd [expr {([initdrops]-$d0)&3}]; set wd [expr {[wdpar]!=$w0}]
  set verdict [expr {$first>=0 ? ($re<=1 ? "CORRECTED" : "DIRTY") : "not seen"}]
  puts [format "%-9s %6d    %3d     %d     %d    %d    %s" $F $first $re $dd $wd [init] $verdict]
  if {$re > 1} { inject 0x1 $F 20 0x8; after 300 }
  drain
}

puts ""
puts "=== C. freeze, inject, thaw INTO HOLD, then release ==="
puts "far       seen_held  first_ms_after_release  rehits  drops  wd   verdict"
foreach F $frames {
  set target [expr {$F+2}]
  drain; set d0 [initdrops]; set w0 [wdpar]
  if {![freeze]} { continue }
  inject 0x881 $F 20 0x8
  thaw 0x41
  set held [first_hit $target 3500]
  drain
  ctrl 0x1
  set first [first_hit $target 3500]
  after 300
  set re [hits_in $target 800]
  set dd [expr {([initdrops]-$d0)&3}]; set wd [expr {[wdpar]!=$w0}]
  set verdict [expr {$re<=1 ? "CORRECTED" : "DIRTY"}]
  puts [format "%-9s %6d     %6d                   %3d     %d     %d    %s" $F $held $first $re $dd $wd $verdict]
  if {$re > 1} { inject 0x1 $F 20 0x8; after 300 }
  drain
}
puts "final: [recword]"
