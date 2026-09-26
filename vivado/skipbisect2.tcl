connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
proc sk {tag} { set v [live]; puts [format "%-30s skip=%d sh=%d alg=%d/%d pc=%d/%d inj=%d/%d arb=%s hto=%d rel=%d" $tag [expr {($v>>3)&1}] [expr {($v>>4)&1}] [expr {($v>>5)&1}] [expr {($v>>6)&1}] [expr {($v>>7)&1}] [expr {($v>>8)&1}] [expr {($v>>25)&1}] [expr {($v>>26)&1}] [lindex {IDLE ARB GRANT END} [expr {($v>>14)&3}]] [hto] [tfrel]] }
set A [expr {(44<<7)|4}]; set B [expr {(44<<7)|6}]
drain; ctrl 0x41; after 50; sk "hold"
ctrl 0xC1; wait_free 500; ctrl 0x8C1; after 20; sk "frozen #1"
inject 0x8C1 $A 10 0x18; sk "A injected (frozen)"
ctrl 0x41; after 60; sk "thawed into hold"
puts "  held captures: [collect 800]"
ctrl 0xC1; set h [wait_free 500]; sk "TEST_FREEZE #2 (handoff=$h)"
ctrl 0x8C1; after 20; sk "frozen #2"
mwr -force 0x43C00000 $B; mwr -force 0x43C00004 11; mwr -force 0x43C00008 0x18
ctrl 0x8C1; after 3; sk "  regs written"
ctrl 0x8C3; after 20; sk "  request up"
ctrl 0x8C7; after 30; sk "  start up"
ctrl 0x8C1; after 20; sk "  done"
ctrl 0x41; after 60; sk "thawed into hold"
puts "  held captures: [collect 1500]   (A+2=[format 0x%06X [expr {$A+2}]] B+2=[format 0x%06X [expr {$B+2}]])"
ctrl 0x1; after 500; sk "released"
inject 0x1 $A 10 0x18; after 200; inject 0x1 $B 11 0x18; after 400; drain; puts "cleanup: [collect 800]"
