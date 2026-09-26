connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
after 3000
proc flags {} { set f [expr {[capf]&7}]; return [format "eccsingle=%d ecc=%d crc=%d" [expr {($f>>2)&1}] [expr {($f>>1)&1}] [expr {$f&1}]] }
puts "word bit   first_ms  flags                       syndrome  rehits  skip  verdict"
foreach v {{49 2} {50 0} {50 2} {50 5} {50 12} {50 13} {50 20} {50 31} {51 2}} {
  lassign $v W B
  set F 0x001304; set target [expr {$F+2}]
  drain
  inject 0x1 $F $W [expr {1<<$B}]
  set t [clock milliseconds]; set first -1; set fl "-"; set syn "-"
  while {[clock milliseconds]-$t < 2500} {
    if {[capf]&2} { if {[capfar]==$target} { set first [expr {[clock milliseconds]-$t}]; set fl [flags]
        set syn [format 0x%04X [expr {[mrd -force -value 0x43C0001C]&0x1FFF}]] }; cc }
    if {$first>=0} break
    after 8 }
  after 300; set re [hits_in $target 800]
  set skip [expr {([live]>>3)&1}]
  set verdict [expr {$first<0 ? "NOT SEEN" : ($re<=1 ? "corrected" : "DIRTY")}]
  puts [format "%-4d %-4d %6d    %-27s %-9s %3d     %d     %s" $W $B $first $fl $syn $re $skip $verdict]
  if {$re>1} { inject 0x1 $F $W [expr {1<<$B}]; after 300 }
  # wait out a skip so the next trial starts clean
  set t1 [clock milliseconds]; while {[clock milliseconds]-$t1 < 6000} { if {!(([live]>>3)&1)} break; after 50 }
  drain
}
puts "final: [livestr [live]]"
