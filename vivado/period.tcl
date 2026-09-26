# Direct measurement of the scan period: plant one upset, hold correction so it
# persists, and timestamp every re-capture for 12 s. The interval between
# captures of the same FAR is the time between two visits = the scan period.
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up

foreach F {0x001304 0x400D12} {
  set target [expr {$F+2}]
  drain
  if {![freeze]} { continue }
  inject 0x881 $F 20 0x8
  thaw 0x41                      ;# hold: the error is never repaired
  set t0 [clock milliseconds]; set ts {}
  while {[clock milliseconds]-$t0 < 12000} {
    if {[capf]&2} {
      if {[capfar] == $target} { lappend ts [expr {[clock milliseconds]-$t0}] }
      cc }
    after 4 }
  set iv {}
  for {set i 1} {$i < [llength $ts]} {incr i} { lappend iv [expr {[lindex $ts $i]-[lindex $ts $i-1]}] }
  puts "$F: captures at ms: $ts"
  puts "$F: intervals: $iv"
  ctrl 0x1; after 3000; drain
}
puts "final: [recword]"
