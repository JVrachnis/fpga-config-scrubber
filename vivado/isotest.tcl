connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
# ctrl reg 0x0C bits: 0 ready,1 request,2 Start,3 desync,4 ack(reset_fifo),5 scan_pause
# isolated injection: pause scan (bit5=1) throughout the inject, then resume (0x00) so
# the scan detects+captures the injected frame's FRAME_ECC syndrome.
proc iso {fr w m} {
  mwr -force 0x43C0000C 0x20;  after 40
  mwr -force 0x43C00000 $fr;   mwr -force 0x43C00004 $w;  mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x30;  after 3;  mwr -force 0x43C0000C 0x20
  mwr -force 0x43C0000C 0x21;  after 4;  mwr -force 0x43C0000C 0x27;  after 40;  mwr -force 0x43C0000C 0x21
  after 40
  mwr -force 0x43C0000C 0x00;  after 400
}
proc rd {} {
  set fl [expr {[mrd -force -value 0x43C00014] & 7}]
  set far [expr {[mrd -force -value 0x43C00018] & 0x03FFFFFF}]
  set syn [expr {[mrd -force -value 0x43C0001C] & 0x1FFF}]
  return [format "flags=0x%X cap_FAR=0x%06X cap_SYN=0x%04X" $fl $far $syn]
}
# let golden-parity init settle with scan running once, then start isolated tests
mwr -force 0x43C0000C 0x00; after 800
puts "=== ISOLATED single-bit injection: vary WORD (frame 0x2000, mask=0x1) ==="
foreach w {5 8 10 11 12 20 31 40 50} {
  iso 0x2000 $w 0x1
  puts [format "  word=%2d : %s" $w [rd]]
}
puts "=== ISOLATED: vary BIT (frame 0x2000, word=10) ==="
foreach m {0x1 0x2 0x4 0x8 0x10 0x100 0x10000 0x40000000} {
  iso 0x2000 10 $m
  puts [format "  mask=0x%08X : %s" $m [rd]]
}
puts "=== ISOLATED: mask=0 should now create NO error ==="
foreach t {1 2 3} {
  mwr -force 0x43C0000C 0x10; after 3; mwr -force 0x43C0000C 0x00; after 200
  iso 0x2000 10 0x0
  puts [format "  trial %d mask=0 : %s" $t [rd]]
}
