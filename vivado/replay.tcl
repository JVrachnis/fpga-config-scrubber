# Beam-data replay.  argv: S [maxEvents]
# Each real event is planted as a set (one hand-off per upset under HOLD),
# released, and watched for 4 s. Verdicts per event:
#   dirty      frames still re-captured after 2.5 s  (visible, uncorrected)
#   livelock   handler busy > 50 % of samples          (beyond capacity)
#   pred       coverage-model prediction encoded in the event name (_p1/_p0)
# A frame whose pattern is ECC-invisible (even multiplicity with cancelling
# syndrome) cannot be seen by this verdict; 'seen_held' reports how many of the
# event's frames were observed while held, so that case is identifiable.
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
set S [lindex $argv 0]
set MAXN [expr {[llength $argv] > 1 ? [lindex $argv 1] : 100000}]
set START [expr {[llength $argv] > 2 ? [lindex $argv 2] : 1}]
after 4000   ;# let the scrubber settle after board_up before the first event
source $::env(SCRUBBER_ROOT)/vivado/replay_events_S$S.tcl
proc freeze_held {} { ctrl 0xC1; if {![wait_free 500]} { ctrl 0x41; return 0 }; ctrl 0x8C1; after 20; return 1 }

puts "CSV,name,frames,upsets,pred,seen_held,dirty,handler_busy_pct,skipped,wd_delta,drops_delta"
set i 0; set agree 0; set n 0
foreach ev $EVENTS {
  incr i; if {$i < $START} { continue }; if {$i > $MAXN} { break }
  set name [lindex $ev 0]; set ups [lrange $ev 1 end]
  regexp {_f(\d+)_b\d+_p(\d)} $name -> nf pred
  drain; ctrl 0x41; after 40
  set w0 [expr {[live]&0x7}]; set d0 [initdrops]
  foreach u $ups { freeze_held; inject 0x8C1 [lindex $u 0] [lindex $u 1] [lindex $u 2]; ctrl 0x41; after 40 }
  set seen [collect 600]
  array unset fr; foreach u $ups { set fr([lindex $u 0]) 1 }
  set seen_held 0; foreach f [array names fr] { if {[lsearch -exact $seen [expr {$f+2}]] >= 0} { incr seen_held } }
  drain; ctrl 0x1
  set t0 [clock milliseconds]; array unset last; foreach f [array names fr] { set last($f) -1 }
  set sh 0; set ns 0; set skipped 0
  while {[clock milliseconds]-$t0 < 4000} {
    set t [expr {[clock milliseconds]-$t0}]
    if {[capf]&2} { set c [capfar]; foreach f [array names fr] { if {$c == $f+2} { set last($f) $t } }; cc }
    set lv [live]; incr ns; incr sh [expr {($lv>>4)&1}]; if {($lv>>3)&1} { set skipped 1 }
    after 10 }
  set dirty 0; foreach f [array names fr] { if {$last($f) > 2500} { incr dirty } }
  set busy [expr {100.0*$sh/$ns}]
  set wdd [expr {(([live]&0xF)-$w0)&0xFF}]; set dd [expr {([initdrops]-$d0)&3}]
  set obs [expr {($dirty==0 && $busy<50 && !$skipped) ? 1 : 0}]
  incr n; if {$obs == $pred} { incr agree }
  puts [format "CSV,%s,%d,%d,%d,%d,%d,%.0f,%d,%d,%d" $name $nf [llength $ups] $pred $seen_held $dirty $busy $skipped $wdd $dd]
  if {$i % 25 == 0} { puts "# $i events, model agreement $agree/$n, [recword]" }
  foreach u $ups { if {$last([lindex $u 0]) > 2500 || $skipped} { inject 0x1 [lindex $u 0] [lindex $u 1] [lindex $u 2]; after 150 } }
  if {$skipped} { set t1 [clock milliseconds]; while {[clock milliseconds]-$t1 < 6000} { if {!(([live]>>3)&1)} { break }; after 50 } }
  after 300; drain
}
puts "=== REPLAY S=$S: $n events, model agreement $agree/$n ==="
puts "final: [livestr [live]]  [recword]"
