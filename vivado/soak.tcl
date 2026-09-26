# Soak: random plain single-bit injections at ~1 per 1.5 s for argv[0] minutes,
# recovery word + live word logged; any hang/blindness caught by the canary.
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
after 2000
set MIN [expr {[llength $argv] ? [lindex $argv 0] : 120}]
source $::env(SCRUBBER_ROOT)/vivado/campaign_vectors_reachable.tcl
set CAN 0x001304
set t0 [clock milliseconds]; set n 0; set miss 0; set alarms 0; set i 0
puts "CSV,minute,injections,misses,drops,wd,skip,alarms"
while {[clock milliseconds]-$t0 < $MIN*60000} {
  set v [lindex $VEC [expr {$i % [llength $VEC]}]]; incr i
  set F [lindex $v 0]; set W [lindex $v 1]; set M [lindex $v 2]
  drain; inject 0x1 $F $W $M; incr n
  if {[first_hit [expr {$F+2}] 1500] < 0} { incr miss }
  after 200; drain
  if {$n % 40 == 0} {
    inject 0x1 $CAN 20 0x8; if {[first_hit [expr {$CAN+2}] 500] < 0} { incr alarms; puts "# CANARY ALARM at $n: [livestr [live]] [recword]"; board_up }
    puts [format "CSV,%d,%d,%d,%d,%d,%d,%d" [expr {([clock milliseconds]-$t0)/60000}] $n $miss [initdrops] [wdpar] [expr {([live]>>3)&1}] $alarms]
  }
}
puts "=== SOAK: $n injections in $MIN min, misses=$miss, alarms=$alarms, [recword] [livestr [live]] ==="
