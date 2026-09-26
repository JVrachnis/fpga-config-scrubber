connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc cc {} { mwr -force 0x43C0000C 0x10; after 3; mwr -force 0x43C0000C 0x0 }
proc doinj {fr w m} { mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1 }
doinj 0x2000 0x0A 0x0; after 600; cc; after 400
# Does the SYNBIT/SYNWORD in the syndrome change if we vary the BIT within a word (mask)?
# For a fixed word, different single-bit masks (bit0..bit4) should give different SYNBIT.
puts "=== vary BIT (mask) at fixed word=10, frame=0x2000: does syndrome change? ==="
foreach m {0x1 0x2 0x4 0x8 0x10 0x100 0x10000} {
  cc; doinj 0x2000 10 $m; after 400
  set syn [expr {[mrd -force -value 0x43C0001C] & 0x1FFF}]
  set fl [expr {[mrd -force -value 0x43C00014] & 7}]
  cc; after 700; set d2 [expr {[mrd -force -value 0x43C00014] & 7}]
  puts [format "  mask=0x%05X : syn=0x%04X flags=0x%X recheck=0x%X" $m $syn $fl $d2]
}
