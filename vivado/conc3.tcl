# Concurrency-capacity campaign (FINDINGS 3/6, finally runnable).
#
# Geometry of this build: group = column, S = 2 subgroups (minor mod 2), G = 64.
# Expected from the code's construction:
#   odd-multiplicity frames  : ECC locates the bit; any number, anywhere
#   even-multiplicity frames : need the subgroup's vertical parity; at most ONE
#                              such frame per subgroup at a time
#
# Each case: plant the set with one hand-off per upset under HOLD_CORRECTION,
# release, watch for 6 s. Per upset: time of last capture (= corrected then) or
# DIRTY if still captured in the final 1.5 s. Plus wd_fires delta and a
# transition log of the live core word.
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up

proc live {} { set b $::CTRLBASE
  mwr -force 0x43C0000C [expr {$b | 0x1200}]; set v [mrd -force -value 0x43C0001C]
  mwr -force 0x43C0000C $b; return $v }
proc wdf {} { return [expr {[live] & 0xFF}] }
proc livestr {v} {
  return [format "wd=%d sh=%d alg=%d/%d pc=%d/%d icap=%d init=%d poi=%d scan=%d wdc=%d alg_dbg=%02x" \
    [expr {$v&0xFF}] [expr {($v>>8)&1}] [expr {($v>>9)&1}] [expr {($v>>10)&1}] [expr {($v>>11)&1}] \
    [expr {($v>>12)&1}] [expr {($v>>13)&1}] [expr {($v>>14)&1}] [expr {($v>>15)&1}] [expr {($v>>16)&3}] \
    [expr {($v>>18)&0x3F}] [expr {($v>>24)&0xFF}]] }
proc freeze_held {} { ctrl 0xC1; if {![wait_free 500]} { puts "  HANDOFF FAILED"; ctrl 0x41; return 0 }
                      ctrl 0x8C1; after 20; return 1 }

# set_: list of {far word mask}
proc runcase {name set_} {
  drain; ctrl 0x41; after 50
  set w0 [wdf]
  foreach u $set_ { freeze_held; inject 0x8C1 [lindex $u 0] [lindex $u 1] [lindex $u 2]; ctrl 0x41; after 60 }
  set seen [collect 2000]
  set held 0; foreach u $set_ { if {[lsearch -exact $seen [expr {[lindex $u 0]+2}]] >= 0} { incr held } }
  drain
  ctrl 0x1
  set t0 [clock milliseconds]
  array set last {}; foreach u $set_ { set last([lindex $u 0]) -1 }
  set prev -1; set trans {}
  while {[clock milliseconds]-$t0 < 8000} {
    set t [expr {[clock milliseconds]-$t0}]
    if {[capf]&2} { set f [capfar]
      foreach u $set_ { if {$f == [lindex $u 0]+2} { set last([lindex $u 0]) $t } }
      cc }
    set v [expr {[live] & 0x0003FFFF}]      ;# transitions on wd count + flags + scan state
    if {$v != $prev} { lappend trans [format "%d:%s" $t [livestr [live]]]; set prev $v }
    after 10 }
  set dirty 0; set tl {}
  foreach u $set_ { set F [lindex $u 0]
    if {$last($F) > 4500} { incr dirty; lappend tl "[format %06X $F]=DIRTY" } else { lappend tl "[format %06X $F]=$last($F)" } }
  set wdd [expr {([wdf]-$w0)&0xFF}]
  puts [format "%-34s planted %d/%d  dirty %d  wd+%d  last-correction(ms): %s" $name $held [llength $set_] $dirty $wdd $tl]
  foreach x $trans { puts "      $x" }
  # cleanup: re-XOR anything still dirty
  foreach u $set_ { set F [lindex $u 0]
    if {$last($F) > 4500} { inject 0x1 $F [lindex $u 1] [lindex $u 2]; after 200 } }
  after 500; drain
}

# frames: top half (bit22=0), columns from the injectable set, minors < 26
proc far {col minor} { return [expr {($col<<7) | $minor}] }



puts "=== E/G with a working live word ==="
runcase "F  2 adj2, col 44, subgroups 0+1 (control)" [list [list [far 44 4] 10 0x18] [list [far 44 5] 11 0x18]]
runcase "E  2 adj2, col 44, SAME subgroup"           [list [list [far 44 4] 10 0x18] [list [far 44 6] 11 0x18]]
puts "after E cleanup: [livestr [live]]  [recword]"
runcase "E  again (repeat)"                          [list [list [far 44 4] 10 0x18] [list [far 44 6] 11 0x18]]
runcase "E2 2 adj2, col 20, same subgroup"           [list [list [far 20 8] 10 0x18] [list [far 20 10] 11 0x18]]
runcase "G  4 adj2, col 44, 2 per subgroup"          [list [list [far 44 4] 10 0x18] [list [far 44 6] 11 0x18] [list [far 44 5] 12 0x18] [list [far 44 7] 13 0x18]]
puts "final: [livestr [live]]  [recword]"
