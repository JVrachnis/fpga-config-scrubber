connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
proc sk {tag} { set v [live]; puts [format "%-34s skip=%d sh=%d pc=%d/%d arb=%s init=%d" $tag [expr {($v>>3)&1}] [expr {($v>>4)&1}] [expr {($v>>7)&1}] [expr {($v>>8)&1}] [lindex {IDLE ARB GRANT END} [expr {($v>>14)&3}]] [expr {($v>>10)&1}]] }
sk "after board_up"; after 1000; sk "after 1 s idle"
puts "background captures 2 s: [collect 2000]"
sk "after collect"
ctrl 0x41; after 200; sk "HOLD on"
ctrl 0xC1; wait_free 500; sk "TEST_FREEZE (hold kept)"
ctrl 0x8C1; after 50; sk "FREEZE_CLK"
ctrl 0x41; after 200; sk "thawed into HOLD"
ctrl 0x1; after 200; sk "released"
ctrl 0x81; wait_free 500; ctrl 0x881; after 50; sk "freeze w/o hold"
ctrl 0x1; after 300; sk "released again"
# single plain injection, correctable
inject 0x1 0x001304 20 0x8; puts "first_hit [first_hit 0x001306 2500]"; after 300; sk "after one correction"
