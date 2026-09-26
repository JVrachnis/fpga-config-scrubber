connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }
proc doinj {fr w m} { mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1 }
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 500

puts "=== E1: background captures, fresh boot, NO injection (30 samples) ==="
array set bg {}
for {set i 0} {$i < 30} {incr i} {
  cc; after 120
  set fl [expr {[mrd -force -value 0x43C00014] & 7}]
  if {$fl & 2} {
    set far [mrd -force -value 0x43C00018]
    set syn [expr {[mrd -force -value 0x43C0001C] & 0x1FFF}]
    set k [format "far=0x%08X syn=0x%04X" $far $syn]
    if {[info exists bg($k)]} { incr bg($k) } else { set bg($k) 1 }
  }
}
foreach k [lsort [array names bg]] { puts "  $k  x$bg($k)" }
if {[array size bg] == 0} { puts "  (no background captures)" }

puts "=== E2: inject at PRISTINE frames - does syndrome track word/bit? ==="
foreach {fr w m} {0x0A00 10 0x8  0x0A00 24 0x8  0x0A00 10 0x100  0x1000 10 0x8  0x1600 33 0x10} {
  cc; after 150
  doinj $fr $w $m; after 400
  set fl [expr {[mrd -force -value 0x43C00014] & 7}]
  set far [mrd -force -value 0x43C00018]
  set syn [expr {[mrd -force -value 0x43C0001C] & 0x1FFF}]
  # correction check with LIVE scanning: ack and see if it recurs
  cc; after 900
  set fl2 [expr {[mrd -force -value 0x43C00014] & 7}]
  set far2 [mrd -force -value 0x43C00018]
  puts [format "  inj far=0x%06X w=%2d m=0x%03X : flags=0x%X cap_far=0x%08X syn=0x%04X | recheck=0x%X (far=0x%08X)" \
        $fr $w $m $fl $far $syn $fl2 $far2]
}
puts "DONE"
