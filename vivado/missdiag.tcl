# Why do ~20% of frozen injections not show up?  Two hypotheses:
#   H1 position-dependent - certain word/bit positions are not ECC-visible
#      (then the SAME (frame,word) fails every time)
#   H2 random  - the injector occasionally does not plant
#      (then repeats of the same (frame,word) differ)
# Repeat each of 8 (frame,word) pairs 5 times, frozen.
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
proc freeze {} { mwr -force 0x43C0000C 0x81; set h [wf 500]
                 mwr -force 0x43C0000C 0x881; after 30; return $h }
proc thaw {} { mwr -force 0x43C0000C 0x1; after 150 }
proc inject {base far word} {
  mwr -force 0x43C00000 $far; mwr -force 0x43C00004 $word; mwr -force 0x43C00008 0x8
  mwr -force 0x43C0000C $base; after 4
  mwr -force 0x43C0000C [expr {$base | 0x6}]; after 60
  mwr -force 0x43C0000C $base; after 40 }
proc watch {target ms} { set t [clock milliseconds]; set n 0
  while {[clock milliseconds]-$t < $ms} {
    if {[mrd -force -value 0x43C00014]&2} {
      if {[expr {[mrd -force -value 0x43C00018]&0xFFFFFF}] == $target} { incr n }; cc }
    after 15 }
  return $n }

set pairs {{0x000600 12} {0x000A00 20} {0x000E00 33} {0x001200 47}
           {0x001600 55} {0x001A00 61} {0x001E00 74} {0x002200 88}}
puts "frame     word  r1 r2 r3 r4 r5   landed/5"
foreach p $pairs {
  set F [lindex $p 0]; set W [lindex $p 1]
  set row {}; set tot 0
  for {set r 0} {$r<5} {incr r} {
    drain
    freeze; inject 0x881 $F $W; thaw
    set n [watch [expr {$F+2}] 1500]
    set hit [expr {$n>0}]
    lappend row $hit; incr tot $hit
    drain
    freeze; inject 0x881 $F $W; thaw      ;# undo
    after 300; drain
  }
  puts [format "%-9s %-5s %s   %d/5" $F $W [join $row " "] $tot]
}
puts "final init=[init]"
