# Separate the two candidate causes of a non-landing injection:
#   sweep A: one frame known to work, word 0..100      -> word dependence
#   sweep B: one word known to work, frame across cols -> frame dependence
# All injections frozen, so the port is guaranteed free every time.
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
proc drain {} { for {set i 0} {$i<40} {incr i} { if {[mrd -force -value 0x43C00014]&2} { cc } else { break } } }
proc wf {ms} { set t [clock milliseconds]
  while {[clock milliseconds]-$t < $ms} { if {[free]} { return 1 }; after 5 }; return 0 }
proc freeze {} { mwr -force 0x43C0000C 0x81; wf 500; mwr -force 0x43C0000C 0x881; after 30 }
proc thaw {} { mwr -force 0x43C0000C 0x1; after 120 }
proc inject {far word} {
  mwr -force 0x43C00000 $far; mwr -force 0x43C00004 $word; mwr -force 0x43C00008 0x8
  mwr -force 0x43C0000C 0x881; after 4
  mwr -force 0x43C0000C 0x887; after 60
  mwr -force 0x43C0000C 0x881; after 40 }
proc watch {target ms} { set t [clock milliseconds]; set n 0
  while {[clock milliseconds]-$t < $ms} {
    if {[mrd -force -value 0x43C00014]&2} {
      if {[expr {[mrd -force -value 0x43C00018]&0xFFFFFF}] == $target} { incr n }; cc }
    after 15 }
  return $n }
proc trial {F W} {
  drain; freeze; inject $F $W; thaw
  set n [watch [expr {$F+2}] 1200]
  drain; freeze; inject $F $W; thaw; after 250; drain
  return [expr {$n>0}] }

puts "=== A. word sweep, frame fixed at 0x001200 (known good) ==="
set row {}
foreach W {0 4 8 12 16 20 24 28 33 40 47 55 61 70 80 88 95 100} {
  set h [trial 0x001200 $W]; lappend row "$W:$h" }
puts [join $row "  "]

puts ""
puts "=== B. frame sweep, word fixed at 47 (known good) ==="
set row {}
foreach F {0x000200 0x000600 0x000A00 0x000E00 0x001200 0x001600 0x001A00 0x001E00
           0x002200 0x002600 0x002A00 0x400200 0x400600 0x400A00 0x400E00 0x401200} {
  set h [trial $F 47]; lappend row "[format %06x $F]:$h" }
puts [join $row "  "]
puts "final init=[init]"
