# Self-upset campaign: flip bits that hold the scrubber's own logic.  argv: N
#
# Targets from selfupset_targets.tcl.out (frame, word, bit, module). Only
# frames in injectable columns are usable (the map of FINDINGS 12). Per trial:
# plain injection of ONE bit of the scrubber, then 3 s of observation:
#   corrected   the frame stops being captured
#   survived    init stayed 1, init_drops unchanged, no watchdog fire, scan
#               still advancing at the end
#   wd_recover  watchdog fired and the scrubber came back (init 1, scanning)
#   DEAD        not scanning after 3 s (scan counter static) -> needs reprogram
# The last case is detected and the board is re-programmed so the campaign
# can continue.
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
set N [expr {[llength $argv] ? [lindex $argv 0] : 200}]
set GOOD {}
for {set c 18} {$c<=27} {incr c} { lappend GOOD $c }; for {set c 34} {$c<=55} {incr c} { lappend GOOD $c }

set fh [open $::env(SCRUBBER_ROOT)/vivado/selfupset_targets.tcl.out r]
set T {}
while {[gets $fh line] >= 0} {
  if {[string match "#*" $line]} { continue }
  lassign $line far word bit mod net
  set col [expr {($far>>7)&0x3FF}]; set half [expr {($far>>22)&1}]
  if {[lsearch -exact $GOOD $col] < 0} { continue }
  if {$half == 1 && $col >= 43} { continue }
  # 2026-09-03 (ILA, FINDINGS 18): bottom cols 19-24 hold the AXI interconnect's
  # SRL read-data FIFOs - dynamic content. A read-modify-write there restores
  # a stale FIFO snapshot into a live AXI converter and hangs the PS bus.
  if {$half == 1 && $col <= 24} { continue }
  lappend T [list $far $word $bit $mod $net]
}
close $fh
puts "usable scrubber bits: [llength $T]"
# deterministic shuffle
set seed 20260903; set S {}
foreach t $T { set seed [expr {($seed*1103515245+12345) & 0x7FFFFFFF}]; lappend S [list $seed $t] }
set T {}; foreach p [lsort -integer -index 0 $S] { lappend T [lindex $p 1] }

puts "CSV,idx,far,word,bit,module,detected,corrected,init,drops,wd,scanning,verdict"
set i 0; array set tally {corrected 0 survived 0 wd_recover 0 DEAD 0 notseen 0 BLIND 0}
foreach t $T {
  incr i; if {$i > $N} { break }
  lassign $t far word bit mod net
  drain
  set w0 [expr {[live]&0x7}]; set d0 [initdrops]
  inject 0x1 $far $word [expr {1<<$bit}]
  set first [first_hit [expr {$far+2}] 2500]
  after 300; set re [hits_in [expr {$far+2}] 600]
  set init [init]; set dd [expr {([initdrops]-$d0)&3}]; set wd [expr {(([live]&0xF)-$w0)&0xFF}]
  set s0 [sc]; after 60; set scanning [expr {[sc] != $s0}]
  set detected [expr {$first>=0}]; set corrected [expr {$detected && $re<=1}]
  if {!$scanning} { set v DEAD } elseif {$wd>0} { set v wd_recover } \
  elseif {!$detected} {
    # blind, or just this bit? plant a known-good control frame and look for it
    inject 0x1 0x001304 20 0x8
    if {[first_hit 0x001306 1500] < 0} { set v BLIND } else { set v notseen }
  } elseif {$corrected && $init && $dd==0} { set v corrected } else { set v survived }
  incr tally($v)
  puts [format "CSV,%d,0x%06X,%d,%d,%s,%d,%d,%d,%d,%d,%d,%s" $i $far $word $bit $mod $detected $corrected $init $dd $wd $scanning $v]
  if {$v eq "DEAD" || $v eq "BLIND"} { puts "# re-programming ($v)"; board_up }
  # a not-seen hit on the scrubber's own frames must not be left in place: it
  # would accumulate into later trials. Restore it (XOR) before moving on.
  if {($re > 1 || $v eq "notseen") && $v ne "DEAD"} { inject 0x1 $far $word [expr {1<<$bit}]; after 200 }
  drain
}
puts "=== SELFUPSET: $i trials: corrected=$tally(corrected) survived=$tally(survived) wd_recover=$tally(wd_recover) DEAD=$tally(DEAD) BLIND=$tally(BLIND) notseen=$tally(notseen) ==="
puts "final: [recword]"
