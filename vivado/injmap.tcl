# Enumerate which frame addresses are actually injectable+detectable.
#
# Per-trial freeze/thaw costs ~12 s, which makes a real sweep impossible, so
# injections are BATCHED: freeze once, plant a single-bit upset in 4 frames
# that sit in 4 different columns (hence 4 different parity groups, so they do
# not compete for the same subgroup), thaw once, then collect every captured
# FAR for 3 s and test membership.  ~1.1 s per frame instead of ~12 s.
#
# Phase 1 validates the batch method against 8 frames whose verdict is already
# known from the per-trial runs.  Phase 2 sweeps the grid.
#
# FAR fields: [22] half, [21:17] row, [16:7] column, [6:0] minor.
connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1500

proc stat {} { return [mrd -force -value 0x43C00010] }
proc free {} { return [expr {([stat]>>4)&1}] }
proc init {} { return [expr {([stat]>>16)&1}] }
proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }
proc drain {} { for {set i 0} {$i<60} {incr i} { if {[mrd -force -value 0x43C00014]&2} { cc } else { break } } }
proc wf {ms} { set t [clock milliseconds]
  while {[clock milliseconds]-$t < $ms} { if {[free]} { return 1 }; after 5 }; return 0 }
proc freeze {} { mwr -force 0x43C0000C 0x81; wf 500; mwr -force 0x43C0000C 0x881; after 20 }
proc thaw {} { mwr -force 0x43C0000C 0x1; after 100 }
proc inject1 {far word mask} {
  mwr -force 0x43C00000 $far; mwr -force 0x43C00004 $word; mwr -force 0x43C00008 $mask
  mwr -force 0x43C0000C 0x881; after 3
  mwr -force 0x43C0000C 0x887; after 45
  mwr -force 0x43C0000C 0x881; after 25 }
proc collect {ms} { set t [clock milliseconds]; set S {}
  while {[clock milliseconds]-$t < $ms} {
    if {[mrd -force -value 0x43C00014]&2} {
      set f [expr {[mrd -force -value 0x43C00018]&0xFFFFFF}]
      if {[lsearch -exact $S $f] < 0} { lappend S $f }
      cc }
    after 8 }
  return $S }

# batch: list of FARs. returns list of 0/1, one per FAR
#
# Thawing straight into free-running mode loses most of the batch: the scrubber
# corrects each upset in ~80 us, so an error usually presents to the sticky
# capture flag once and a ~8 ms JTAG poll walks right past it.  Measured that
# way, two frames with a known 3/3 per-trial verdict read as 0.
#
# So thaw into HOLD_CORRECTION (CTRL bit6) instead: detection still latches and
# the AXI capture path is unfiltered, but nothing gets repaired, so every planted
# upset is re-detected on every 3.3 ms sweep and the poll cannot miss it.
# Release the hold afterwards and let the scrubber clean up the batch.
proc runbatch {batch} {
  drain
  freeze
  set w 20
  foreach F $batch { inject1 $F $w 0x8; incr w 7 }
  mwr -force 0x43C0000C 0x41       ;# thaw with the corrector held
  after 150
  set seen [collect 2500]
  set out {}
  foreach F $batch { lappend out [expr {[lsearch -exact $seen [expr {$F+2}]] >= 0}] }
  mwr -force 0x43C0000C 0x1        ;# release: let it repair the whole batch
  after 600
  drain
  return $out
}

puts "=== phase 1: batch method vs known per-trial verdicts ==="
puts "expected: 0x40110C 1, 0x001603 1, 0x4019A0 1, 0x000A00 1"
puts "          0x40109C 0, 0x401022 0, 0x400E18 0, 0x400102 0"
puts "got good: [runbatch {0x40110C 0x001603 0x4019A0 0x000A00}]"
puts "got bad : [runbatch {0x40109C 0x401022 0x400E18 0x400102}]"

puts ""
puts "=== phase 2: grid sweep ==="
puts "CSV far,half,row,col,minor,injectable"
set grid {}
foreach half {0 1} {
  foreach minor {0 4 12 20 28 36} {
    foreach col {0 2 4 8 12 16 20 24 28 32 36 40 44 48 52 55 56 58 60} {
      lappend grid [expr {($half<<22) | ($col<<7) | $minor}]
    }
  }
}
puts "# grid points: [llength $grid]"
set n 0
while {$n < [llength $grid]} {
  set batch [lrange $grid $n [expr {$n+3}]]
  set res [runbatch $batch]
  foreach F $batch r $res {
    puts [format "CSV,0x%06X,%d,%d,%d,%d,%d" $F [expr {($F>>22)&1}] [expr {($F>>17)&0x1F}] \
          [expr {($F>>7)&0x3FF}] [expr {$F&0x7F}] $r]
  }
  incr n 4
  if {$n % 40 == 0} { puts "# progress $n/[llength $grid] init=[init]" }
}
puts "# done init=[init]"
