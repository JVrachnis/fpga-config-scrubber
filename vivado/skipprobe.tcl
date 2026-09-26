connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
proc freeze_held {} { ctrl 0xC1; if {![wait_free 500]} { return 0 }; ctrl 0x8C1; after 20; return 1 }
set A [expr {(44<<7)|4}]; set B [expr {(44<<7)|6}]
drain; ctrl 0x41; after 50
freeze_held; inject 0x8C1 $A 10 0x18; ctrl 0x41; after 60
freeze_held; inject 0x8C1 $B 11 0x18; ctrl 0x41; after 60
puts "held: [collect 1500]"
drain; ctrl 0x1
set t0 [clock milliseconds]; set prev ""
puts "ms     event"
while {[clock milliseconds]-$t0 < 9000} {
  set t [expr {[clock milliseconds]-$t0}]
  if {[capf]&2} { set f [capfar]; set tag [expr {$f==$A+2 ? "A" : ($f==$B+2 ? "B" : [format 0x%06X $f])}]
    puts [format "%-6d capture %s" $t $tag]; cc }
  set v [live]; set st [format "skip=%d sh=%d alg=%d" [expr {($v>>3)&1}] [expr {($v>>4)&1}] [expr {($v>>5)&1}]]
  if {$st ne $prev} { puts [format "%-6d %s" $t $st]; set prev $st }
  after 10 }
ctrl 0x41; after 100
puts "state of the pair under HOLD at the end: [collect 1500]  (A+2=[format 0x%06X [expr {$A+2}]] B+2=[format 0x%06X [expr {$B+2}]])"
ctrl 0x1
# cleanup
inject 0x1 $A 10 0x18; after 200; inject 0x1 $B 11 0x18; after 400; drain
puts "after cleanup: [collect 1000]"
