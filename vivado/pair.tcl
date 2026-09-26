# Can the injector plant TWO upsets in one freeze?  (review item 3)
#
# Batching 4 injections per freeze lost frames with a known 3/3 verdict, with
# the pattern 1 0 0 1 twice. The concurrency experiments need multiple
# simultaneous upsets, so this has to be understood.
#
# Every pair is thawed into HOLD_CORRECTION so nothing is repaired, and every
# distinct captured FAR is collected for 3 s. Variants:
#   V1  A then B, fixed 45 ms gap (what the batch did)
#   V2  A then B, wait for STATUS.busy = 0 between them
#   V3  A then B, 300 ms gap
#   V4  B then A, fixed gap (order dependence)
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up

proc wait_notbusy {ms} { set t [clock milliseconds]
  while {[clock milliseconds]-$t < $ms} { if {![busy]} { return 1 }; after 2 }; return 0 }

proc pairtrial {A B mode} {
  drain
  if {![freeze]} { return "nofreeze" }
  switch $mode {
    V1 { inject 0x881 $A 20 0x8; inject 0x881 $B 30 0x8 }
    V2 { inject 0x881 $A 20 0x8; set ok [wait_notbusy 500]; inject 0x881 $B 30 0x8 }
    V3 { inject 0x881 $A 20 0x8; after 300; inject 0x881 $B 30 0x8 }
    V4 { inject 0x881 $B 30 0x8; inject 0x881 $A 20 0x8 }
  }
  thaw 0x41
  set seen [collect 3000]
  set a [expr {[lsearch -exact $seen [expr {$A+2}]] >= 0}]
  set b [expr {[lsearch -exact $seen [expr {$B+2}]] >= 0}]
  ctrl 0x1; after 800; drain
  return "A=$a B=$b"
}

set pairs {{0x000A14 0x001606} {0x400B09 0x001304} {0x001919 0x400D12} {0x000C08 0x401220}}
puts "pair                 V1(45ms)   V2(busy=0)  V3(300ms)  V4(B then A)"
foreach p $pairs {
  set A [lindex $p 0]; set B [lindex $p 1]
  puts [format "%-9s %-9s  %-10s %-11s %-10s %s" $A $B \
    [pairtrial $A $B V1] [pairtrial $A $B V2] [pairtrial $A $B V3] [pairtrial $A $B V4]]
}
puts "final: [recword]"
