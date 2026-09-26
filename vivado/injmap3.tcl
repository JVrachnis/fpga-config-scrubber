# Complete the injectable-column map and test the col >= 56 result.
#
# The sparse sweep found injectability to be a pure function of the FAR column,
# uniform across minors.  Two gaps to close:
#   1. columns were sampled every 4; fill in every column 0..60
#   2. columns 56/58/60 came back 36/36 "injectable", but col 56 is the known
#      out-of-device artifact region (0x001C02 is in masked_frames_c).  If that
#      region raises ECC events on its own, a capture at FAR+2 proves nothing.
#      CONTROL: run the identical trial with the injection step SKIPPED.  A
#      "detection" with nothing planted is a false positive.
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
# do_inject 0 = control: freeze and thaw exactly as usual, but plant nothing
proc trial {F do_inject} {
  drain
  mwr -force 0x43C0000C 0x81; wf 500; mwr -force 0x43C0000C 0x881; after 20
  if {$do_inject} {
    mwr -force 0x43C00000 $F; mwr -force 0x43C00004 20; mwr -force 0x43C00008 0x8
    mwr -force 0x43C0000C 0x881; after 3
    mwr -force 0x43C0000C 0x887; after 45
    mwr -force 0x43C0000C 0x881; after 25
  } else { after 73 }
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

puts "=== controls: same trial, nothing planted ==="
puts "col  far        injected  control"
foreach col {20 24 40 52 55 56 58 60} {
  set F [expr {($col<<7)}]
  puts [format "%-4d 0x%06X   %d         %d" $col $F [trial $F 1] [trial $F 0]]
}

puts ""
puts "=== every column 0..60, minor 0 and minor 8, both halves ==="
puts "CSV,far,half,col,minor,injectable"
foreach half {0 1} {
  foreach minor {0 8} {
    for {set col 0} {$col <= 60} {incr col} {
      set F [expr {($half<<22) | ($col<<7) | $minor}]
      puts [format "CSV,0x%06X,%d,%d,%d,%d" $F $half $col $minor [trial $F 1]]
    }
    puts "# half=$half minor=$minor done init=[init]"
  }
}
puts "# done init=[init]"
