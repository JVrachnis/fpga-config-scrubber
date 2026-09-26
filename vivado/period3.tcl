# Timeline of EVERY capture for 14 s with one persistent upset held in each
# half. The background artifacts (col 56 etc.) show the pass cadence; the two
# held upsets show when each half is visited.
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up

set A 0x001304 ; set B 0x400D12
drain
freeze
inject 0x881 $A 20 0x8   ;# single injection only
thaw 0x41
set t0 [clock milliseconds]
puts "ms      far        note"
while {[clock milliseconds]-$t0 < 16000} {
  if {[capf]&2} {
    set f [capfar]; set t [expr {[clock milliseconds]-$t0}]
    set note ""
    if {$f == $A+2} { set note "<- A (top, col 38)" }
    if {$f == $B+2} { set note "<- B (bottom, col 26)" }
    puts [format "%-7d 0x%06X   %s" $t $f $note]
    cc }
  after 3 }
puts "scan counter now [sc]; [recword]"
ctrl 0x1; after 3000; drain
puts "after release: [recword]"
