# Acceptance run for the mid-correction freeze, on the validated campaign
# vectors (the same frame list the 150/150 campaign used), paired
# frozen vs plain.
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
proc thaw {} { mwr -force 0x43C0000C 0x1; after 120 }
proc inject {base far word mask} {
  mwr -force 0x43C00000 $far; mwr -force 0x43C00004 $word; mwr -force 0x43C00008 $mask
  mwr -force 0x43C0000C $base; after 4
  mwr -force 0x43C0000C [expr {$base | 0x6}]; after 60
  mwr -force 0x43C0000C $base; after 40 }
proc watch {target ms} { set t [clock milliseconds]; set n 0
  while {[clock milliseconds]-$t < $ms} {
    if {[mrd -force -value 0x43C00014]&2} {
      if {[expr {[mrd -force -value 0x43C00018]&0xFFFFFF}] == $target} { incr n }; cc }
    after 15 }
  return $n }

source $::env(SCRUBBER_ROOT)/vivado/campaign_vectors.tcl
set vec $VEC

puts "n   FAR       word mode    handoff landed"
set rf 0; set rp 0; set nf 0; set np 0; set i 0
foreach v $vec {
  incr i
  if {$i > 30} { break }
  set F [lindex $v 0]; set W [lindex $v 1]; set M [lindex $v 2]
  set frozen [expr {$i % 2}]
  drain
  if {$frozen} { incr nf; set h [freeze]; inject 0x881 $F $W $M; thaw } \
  else         { incr np; set h "-"; inject 0x1 $F $W $M }
  set n [watch [expr {[expr {$F}]+2}] 1500]
  if {$n>0} { if {$frozen} {incr rf} else {incr rp} }
  puts [format "%-3d %-9s %-4s %-7s %-7s %s" $i $F $W \
        [expr {$frozen?"FROZEN":"plain"}] $h [expr {$n>0}]]
  drain
  if {$frozen} { freeze; inject 0x881 $F $W $M; thaw } else { inject 0x1 $F $W $M }
  after 300; drain
}
puts ""
puts "FROZEN landed: $rf / $nf"
puts "plain  landed: $rp / $np"
puts "final init=[init]"
