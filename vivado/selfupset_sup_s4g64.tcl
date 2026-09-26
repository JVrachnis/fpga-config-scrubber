# Self-upset under a supervisor, s4g64 build targets (from /tmp/map_s4g64 .ll/.ebd, morning 2026-09-04).  argv: N
# Emulates the PS-side monitor a deployed system would run:
#   heartbeat  the scan counter must advance within 60 ms
#   canary     a bit flipped in a known-empty frame (0x001304 w20 b3) must be
#              captured within 300 ms  -> detects BLIND
# After each essential-bit hit the supervisor polls; the first failed check is
# the ALARM (t_alarm - t_hit = detection latency of the failure); it then
# reprograms and waits for init=1 + a passing canary (t_recovered).
# Also counts false alarms on trials the scrubber survived.
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
after 2000
set N [expr {[llength $argv] ? [lindex $argv 0] : 200}]
set CAN 0x001304
proc heartbeat_ok {} { set a [sc]; after 60; return [expr {[sc] != $a}] }
proc canary_ok {} { drain; inject 0x1 $::CAN 20 0x8; set h [first_hit [expr {$::CAN+2}] 300]
  if {$h < 0} { return 0 }; after 100; return 1 }
proc supervise {tmax} {   ;# returns {verdict ms}
  set t0 [clock milliseconds]
  while {[clock milliseconds]-$t0 < $tmax} {
    if {![heartbeat_ok]} { return [list DEAD [expr {[clock milliseconds]-$t0}]] }
    if {![canary_ok]}    { return [list BLIND [expr {[clock milliseconds]-$t0}]] }
    after 100 }
  return [list alive $tmax] }
proc recover {} { set t0 [clock milliseconds]; board_up
  for {set i 0} {$i<20} {incr i} { if {[init] && [canary_ok]} { return [expr {[clock milliseconds]-$t0}] }; after 200 }
  return -1 }

set GOOD {}; for {set c 25} {$c<=27} {incr c} { lappend GOOD $c }; for {set c 34} {$c<=42} {incr c} { lappend GOOD $c }
set fh [open $::env(SCRUBBER_ROOT)/vivado/selfupset_targets_s4g64.tcl.out r]; set T {}
while {[gets $fh line] >= 0} { if {[string match "#*" $line]} continue
  lassign $line far word bit kind net; set col [expr {($far>>7)&0x3FF}]
  if {[lsearch -exact $GOOD $col] < 0 || $kind ne "ebd1"} continue
  lappend T [list $far $word $bit] }
close $fh
set seed 20260904; set S {}
foreach t $T { set seed [expr {($seed*1103515245+12345) & 0x7FFFFFFF}]; lappend S [list $seed $t] }
set T {}; foreach p [lsort -integer -index 0 $S] { lappend T [lindex $p 1] }
puts "targets: [llength $T]"
puts "CSV,idx,far,word,bit,verdict,alarm_ms,recover_ms"
set i 0; array set tally {alive 0 DEAD 0 BLIND 0}; set alarms {}; set recs {}
foreach t $T {
  incr i; if {$i > $N} break
  lassign $t far w b
  drain
  inject 0x1 $far $w [expr {1<<$b}]
  lassign [supervise 2500] v ms
  incr tally($v)
  set rec -1
  if {$v ne "alive"} { set rec [recover]; lappend alarms $ms; lappend recs $rec } else { inject 0x1 $far $w [expr {1<<$b}]; after 100 }
  puts [format "CSV,%d,0x%06X,%d,%d,%s,%d,%d" $i $far $w $b $v $ms $rec]
  drain
}
proc med {L} { if {![llength $L]} { return -1 }; set s [lsort -integer $L]; return [lindex $s [expr {[llength $s]/2}]] }
puts "=== SUPERVISED: $i trials  alive=$tally(alive) DEAD=$tally(DEAD) BLIND=$tally(BLIND)  alarm median [med $alarms] ms  recovery median [med $recs] ms ==="
