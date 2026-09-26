# Capacity campaign parameterized by S (subgroups per group).  argv: S
#   subgroup = minor mod S. Expected: k even-multiplicity frames in one column
#   correct iff they occupy k DISTINCT subgroups; the (S+1)-th, or any two in
#   one subgroup, are beyond capacity (livelock, no write).
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
set S [expr {[llength $argv] ? [lindex $argv 0] : 2}]
proc freeze_held {} { ctrl 0xC1; if {![wait_free 500]} { puts "  HANDOFF FAILED"; ctrl 0x41; return 0 }
                      ctrl 0x8C1; after 20; return 1 }
proc far {col minor} { return [expr {($col<<7) | $minor}] }
proc runcase {name set_} {
  global S
  drain; ctrl 0x41; after 50
  foreach u $set_ { freeze_held; inject 0x8C1 [lindex $u 0] [lindex $u 1] [lindex $u 2]; ctrl 0x41; after 60 }
  drain; ctrl 0x1
  set t0 [clock milliseconds]; array set last {}; foreach u $set_ { set last([lindex $u 0]) -1 }
  set shbusy 0; set n 0; set algreq 0
  while {[clock milliseconds]-$t0 < 5000} {
    set t [expr {[clock milliseconds]-$t0}]
    if {[capf]&2} { set f [capfar]; foreach u $set_ { if {$f == [lindex $u 0]+2} { set last([lindex $u 0]) $t } }; cc }
    set v [live]; incr n; incr shbusy [expr {($v>>4)&1}]; incr algreq [expr {($v>>5)&1}]
    after 10 }
  set dirty 0; foreach u $set_ { if {$last([lindex $u 0]) > 3500} { incr dirty } }
  puts [format "CSV,S=%d,%s,%d,%d,%.0f,%d,%d" $S $name [llength $set_] $dirty [expr {100.0*$shbusy/$n}] $algreq [expr {[live]&0x7}]]
  puts [format "  %-40s n=%d dirty=%d  handler-busy %.0f%%  alg-req samples %d" $name [llength $set_] $dirty [expr {100.0*$shbusy/$n}] $algreq]
  foreach u $set_ { if {$last([lindex $u 0]) > 3500} { inject 0x1 [lindex $u 0] [lindex $u 1] [lindex $u 2]; after 200 } }
  after 500; drain }

puts "CSV,config,case,n,dirty,handler_busy_pct,alg_req_samples,wd_fires"
# singles, independent columns
set cols {20 36 40 44 48 52 24 26 38 50 18 19 21 23 25 27}
foreach N {4 16} { set s {}; for {set i 0} {$i<$N} {incr i} { lappend s [list [far [lindex $cols $i] [expr {4+$i}]] [expr {10+$i}] 0x8] }
  runcase "singles_${N}_cols" $s }
# even-multiplicity frames in ONE column, k distinct subgroups, k = 1..S+1
for {set k 1} {$k <= $S+1} {incr k} {
  set s {}; for {set i 0} {$i<$k} {incr i} { lappend s [list [far 44 [expr {4+$i}]] [expr {10+$i}] 0x18] }
  runcase "adj2_x${k}_col44_distinct_subgroups" $s }
# two even-multiplicity frames in the SAME subgroup (minor and minor+S)
runcase "adj2_x2_col44_same_subgroup" [list [list [far 44 4] 10 0x18] [list [far 44 [expr {4+$S}]] 11 0x18]]
# S even-multiplicity frames per column across 4 columns
set s {}; foreach c {20 36 40 48} { for {set i 0} {$i<$S} {incr i} { lappend s [list [far $c [expr {4+$i}]] [expr {10+$i}] 0x18] } }
runcase "adj2_S_per_col_x4cols" $s
puts "final: [livestr [live]]  [recword]"
