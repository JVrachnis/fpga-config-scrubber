connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
proc live {} { set b $::CTRLBASE
  mwr -force 0x43C0000C [expr {$b | 0x1000}]; set v [mrd -force -value 0x43C0001C]
  mwr -force 0x43C0000C $b; return $v }
puts "idle, 8 reads: STATUS init / live raw"
for {set i 0} {$i<8} {incr i} { puts [format "  init=%d  live=0x%08X" [init] [live]]; after 50 }
puts "select bit held, then read (no toggling):"
mwr -force 0x43C0000C 0x1001; after 5
for {set i 0} {$i<4} {incr i} { puts [format "  live=0x%08X" [mrd -force -value 0x43C0001C]]; after 50 }
puts "other selects for comparison:"
mwr -force 0x43C0000C 0x101; puts [format "  us_timer   0x%08X" [mrd -force -value 0x43C0001C]]
mwr -force 0x43C0000C 0x201; puts [format "  frames_ctr 0x%08X" [mrd -force -value 0x43C0001C]]
mwr -force 0x43C0000C 0x1201; puts [format "  live|sel2  0x%08X" [mrd -force -value 0x43C0001C]]
mwr -force 0x43C0000C 0x1
# old (simultaneous request+start) injection protocol, to attribute the tail
proc inject_old {base far word mask} {
  mwr -force 0x43C00000 $far; mwr -force 0x43C00004 $word; mwr -force 0x43C00008 $mask
  ctrl $base; after 3; ctrl [expr {$base | 0x6}]; after 45; ctrl $base; after 25 }
proc freeze_held {} { ctrl 0xC1; if {![wait_free 500]} { return 0 }; ctrl 0x8C1; after 20; return 1 }
puts ""
puts "=== tail attribution: 4 mixed-half singles, OLD protocol, 3 repeats ==="
foreach r {1 2 3} {
  set set_ {0x000A14 0x400B09 0x001919 0x000C08}
  drain; ctrl 0x41; after 50; set w 20; set w0 [wdpar]
  foreach F $set_ { freeze_held; inject_old 0x8C1 $F $w 0x8; incr w 7; ctrl 0x41; after 60 }
  set seen [collect 1500]; set held 0
  foreach F $set_ { if {[lsearch -exact $seen [expr {$F+2}]] >= 0} { incr held } }
  drain; ctrl 0x1
  set t0 [clock milliseconds]; array unset last; foreach F $set_ { set last($F) -1 }
  while {[clock milliseconds]-$t0 < 5000} {
    if {[capf]&2} { set f [capfar]; foreach F $set_ { if {$f == $F+2} { set last($F) [expr {[clock milliseconds]-$t0}] } }; cc }
    after 10 }
  set tl {}; foreach F $set_ { lappend tl "[format %06X $F]=$last($F)" }
  puts "  r$r held $held/4  wd_flip=[expr {[wdpar]!=$w0}]  last capture ms: $tl"
  foreach F $set_ { if {$last($F) > 3500} { inject 0x1 $F 20 0x8; after 200 } }
  after 400; drain
}
