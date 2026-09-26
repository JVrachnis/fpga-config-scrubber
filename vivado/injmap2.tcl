# Enumerate which frame addresses are actually injectable + detectable.
#
# Method: one frozen single-bit injection per frame, 2500 ms observation.
# That is the method already shown to be deterministic (3/3 or 0/3 on repeats).
#
# Batching 4 frames per freeze cycle was tried first and abandoned: two frames
# with a known 3/3 verdict read as 0 in a batch, both with the corrector free
# and with it held.  Per-trial costs ~4 s, so the whole grid is ~15 min anyway.
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
proc trial {F} {
  drain
  mwr -force 0x43C0000C 0x81; wf 500; mwr -force 0x43C0000C 0x881; after 20
  mwr -force 0x43C00000 $F; mwr -force 0x43C00004 20; mwr -force 0x43C00008 0x8
  mwr -force 0x43C0000C 0x881; after 3
  mwr -force 0x43C0000C 0x887; after 45
  mwr -force 0x43C0000C 0x881; after 25
  mwr -force 0x43C0000C 0x1; after 100
  set target [expr {$F+2}]
  set t [clock milliseconds]; set hit 0
  while {[clock milliseconds]-$t < 2500} {
    if {[mrd -force -value 0x43C00014]&2} {
      if {[expr {[mrd -force -value 0x43C00018]&0xFFFFFF}] == $target} { set hit 1 }
      cc }
    if {$hit} { break }
    after 10
  }
  after 200; drain
  return $hit
}

puts "=== sanity: known verdicts ==="
foreach F {0x40110C 0x001603 0x4019A0 0x40109C 0x401022 0x400102} {
  puts [format "  %-9s -> %d" $F [trial $F]] }

puts ""
puts "=== grid sweep ==="
puts "CSV,far,half,col,minor,injectable"
set grid {}
foreach half {0 1} {
  foreach minor {0 4 12 20 28 36} {
    foreach col {0 2 4 8 12 16 20 24 28 32 36 40 44 48 52 55 56 58 60} {
      lappend grid [expr {($half<<22) | ($col<<7) | $minor}] } } }
set N [llength $grid]
puts "# grid points: $N"
set i 0
foreach F $grid {
  incr i
  set r [trial $F]
  puts [format "CSV,0x%06X,%d,%d,%d,%d" $F [expr {($F>>22)&1}] \
        [expr {($F>>7)&0x3FF}] [expr {$F&0x7F}] $r]
  if {$i % 25 == 0} { puts "# progress $i/$N init=[init]" }
}
puts "# done init=[init]"
