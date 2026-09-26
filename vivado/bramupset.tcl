# BRAM-content upsets: argv = kind N   (kind: golden | calc | algorithm)
# Per trial: flip one memory bit (block-type-1 frame, persistent - the scan
# never visits it), then
#   regen   init_drops advanced within 1.5 s  (byte parity caught it, golden rebuilt)
#   poi     parity_poisoned seen
#   wd      watchdog fired
#   spot    8 spot-check corrections afterwards: 4 single-bit (ECC path) and
#           4 adj2 (parity path, which is what reads the golden store); count
#           corrected, flag any left dirty or any skip
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
after 3000
set KIND [lindex $argv 0]; set N [expr {[llength $argv] > 1 ? [lindex $argv 1] : 50}]
set T {}
set fh [open $::env(SCRUBBER_ROOT)/vivado/bram_targets.tcl.out r]
while {[gets $fh line] >= 0} { if {[string match "#*" $line]} continue
  lassign $line far w b kind site; if {$kind eq $KIND} { lappend T [list $far $w $b $site] } }
close $fh
puts "targets for $KIND: [llength $T]"
set SPOT {{0x000A08 20 0x8} {0x001208 33 0x8} {0x001608 47 0x8} {0x001A08 61 0x8}
          {0x000C0A 12 0x18} {0x001408 40 0x18} {0x001808 55 0x18} {0x400B0A 27 0x18}}
proc spotcheck {} {
  set ok 0; set dirty 0; set skip 0
  foreach s $::SPOT {
    lassign $s F W M; drain
    inject 0x1 $F $W $M
    set h [first_hit [expr {$F+2}] 1500]; after 150; set re [hits_in [expr {$F+2}] 400]
    if {$h >= 0 && $re <= 1} { incr ok } elseif {$re > 1} { incr dirty; inject 0x1 $F $W $M; after 150 }
    if {([live]>>3)&1} { set skip 1 }
  }
  drain; return [list $ok $dirty $skip] }
puts "CSV,idx,far,word,bit,site,regen_ms,drops,poi,wd,spot_ok,spot_dirty,skip"
set i 0; array set tally {regen 0 silent 0 miscorr 0 wd 0}
foreach t $T {
  incr i; if {$i > $N} break
  lassign $t far w b site
  drain
  set d0 [initdrops]; set w0 [wdf]
  # A block-type-1 frame holds a slice of EVERY BRAM in the column; the
  # injector's read-modify-write would put stale data back into the live
  # memories sharing the column with the golden store. Inject with the core
  # clock stopped so the writeback is exact and only the one bit changes.
  if {![freeze]} { puts "# freeze failed at trial $i"; continue }
  inject 0x881 $far $w [expr {1<<$b}]
  thaw
  set t0 [clock milliseconds]; set regen -1; set poi 0
  while {[clock milliseconds]-$t0 < 1500} {
    set lv [live]; if {($lv>>11)&1} { set poi 1 }
    if {(([initdrops]-$d0)&3) != 0 && $regen < 0} { set regen [expr {[clock milliseconds]-$t0}] }
    after 10 }
  set dd [expr {([initdrops]-$d0)&3}]; set wd [expr {([wdf]-$w0)&7}]
  lassign [spotcheck] sok sdirty sskip
  set v [expr {$wd ? "wd" : ($sdirty ? "miscorr" : ($dd ? "regen" : "silent"))}]
  incr tally($v)
  puts [format "CSV,%d,%s,%d,%d,%s,%d,%d,%d,%d,%d,%d,%d" $i $far $w $b $site $regen $dd $poi $wd $sok $sdirty $sskip]
  # restore the memory bit (XOR) so hits do not accumulate; a regen already rebuilt golden
  if {$KIND ne "golden" || !$dd} { freeze; inject 0x881 $far $w [expr {1<<$b}]; thaw; after 100 }
  drain
}
puts "=== BRAMUPSET $KIND: $i trials  regen=$tally(regen) silent=$tally(silent) miscorr=$tally(miscorr) wd=$tally(wd) ==="
puts "final: [livestr [live]]  [recword]"
