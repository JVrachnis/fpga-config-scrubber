# Case 3 in detail: 2 EVEN-multiplicity frames in the SAME subgroup.
# The pass/fail criterion used before ("<=2 captures") cannot distinguish
#   "detected once, then corrected"      (1-2 captures)  from
#   "never appeared at all"              (0 captures)
# and the second would mean the upset was never really staged. Count explicitly,
# and also verify each frame individually so a missing plant cannot hide.
connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1500
proc hold_on  {} { mwr -force 0x43C0000C 0x41; after 25 }
proc hold_off {} { mwr -force 0x43C0000C 0x1;  after 25 }
proc inj_h {fr w m} {
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x41; after 4; mwr -force 0x43C0000C 0x47; after 60; mwr -force 0x43C0000C 0x41
}
# poll WITHOUT clearing first, so a latched capture is not thrown away
proc watch {ms} {
  set t [clock milliseconds]; array set seen {}
  while {[clock milliseconds]-$t < $ms} {
    if {[expr {[mrd -force -value 0x43C00014] & 2}]} {
      set f [format 0x%06X [expr {[mrd -force -value 0x43C00018]&0xFFFFFF}]]
      set s [format 0x%04X [expr {[mrd -force -value 0x43C0001C]&0x1FFF}]]
      set k "$f/$s"
      if {[info exists seen($k)]} {incr seen($k)} else {set seen($k) 1}
      mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1
    }
    after 20
  }
  return [array get seen]
}
set A 0x001800   ;# minor 0, subgroup 0
set B 0x001802   ;# minor 2, subgroup 0  (same subgroup)

puts "=== A alone (even, adj2) - baseline that the plant works ==="
hold_on; inj_h $A 10 0x300; hold_off
puts "   captures: [watch 1500]"
after 500
puts "=== B alone (even, adj2, different syndrome) ==="
hold_on; inj_h $B 50 0xC00; hold_off
puts "   captures: [watch 1500]"
after 500
puts "=== A and B staged CONCURRENTLY (same subgroup, different syndromes) ==="
hold_on
inj_h $A 10 0x300
inj_h $B 50 0xC00
hold_off
puts "   captures: [watch 2500]"
after 500
puts "=== residual check (any frame still erroring?) ==="
puts "   captures: [watch 1500]"
puts "final init=[expr {([mrd -force -value 0x43C00010]>>16)&1}]"
