# Supervisor (heartbeat + canary, as selfupset_sup.tcl) applied to KNOWN failure bits.
# argv: REPS far word bit [far word bit ...]   — each vector REPS times, fresh board before each.
# Measures: verdict (alive/DEAD/BLIND), alarm latency, recovery time for the bits that
# broke the campaigns (prod re-capture loops, s4g64 freeze/loop).  Morning 2026-09-04.
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
after 2000
set REPS [lindex $argv 0]
set VEC {}
for {set k 1} {$k + 2 < [llength $argv] + 1} {incr k 3} { lappend VEC [lrange $argv $k [expr {$k+2}]] }
set CAN 0x001304
proc heartbeat_ok {} { set a [sc]; after 60; return [expr {[sc] != $a}] }
proc canary_ok {} { drain; inject 0x1 $::CAN 20 0x8; set h [first_hit [expr {$::CAN+2}] 300]
  if {$h < 0} { return 0 }; after 100; return 1 }
proc supervise {tmax} {
  set t0 [clock milliseconds]
  while {[clock milliseconds]-$t0 < $tmax} {
    if {![heartbeat_ok]} { return [list DEAD [expr {[clock milliseconds]-$t0}]] }
    if {![canary_ok]}    { return [list BLIND [expr {[clock milliseconds]-$t0}]] }
    after 100 }
  return [list alive $tmax] }
proc recover {} { set t0 [clock milliseconds]; board_up
  for {set i 0} {$i<20} {incr i} { if {[init] && [canary_ok]} { return [expr {[clock milliseconds]-$t0}] }; after 200 }
  return -1 }
puts "vectors: $VEC  x$REPS"
puts "CSV,idx,far,word,bit,verdict,alarm_ms,recover_ms,canary_before"
set i 0; array set tally {alive 0 DEAD 0 BLIND 0}; set alarms {}; set recs {}
foreach v $VEC {
  lassign $v far w b
  for {set r 0} {$r < $REPS} {incr r} {
    incr i
    set cb [canary_ok]
    drain
    inject 0x1 $far $w [expr {1<<$b}]
    lassign [supervise 4000] verdict ms
    incr tally($verdict)
    set rec -1
    if {$verdict ne "alive"} { set rec [recover]; lappend alarms $ms; lappend recs $rec } else { board_up; after 2000 }
    puts [format "CSV,%d,%s,%d,%d,%s,%d,%d,%d" $i $far $w $b $verdict $ms $rec $cb]
    drain
  }
}
proc med {L} { if {![llength $L]} { return -1 }; set s [lsort -integer $L]; return [lindex $s [expr {[llength $s]/2}]] }
puts "=== SUPERVISED-KNOWN: $i trials  alive=$tally(alive) DEAD=$tally(DEAD) BLIND=$tally(BLIND)  alarm median [med $alarms] ms  recovery median [med $recs] ms ==="
