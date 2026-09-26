connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc cc {} { mwr -force 0x43C0000C 0x10; after 3; mwr -force 0x43C0000C 0x0 }
proc doinj {fr w m} { mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 45; mwr -force 0x43C0000C 0x1 }
doinj 0x2000 0x0A 0x0; after 500; cc; after 300
puts "=== FAR + syndrome vs injected FRAME (word fixed=10, mask=1) ==="
foreach fr {0x2000 0x2080 0x2100 0x4000 0x4080 0x8000} {
  cc; doinj $fr 10 0x1; after 350
  set far [mrd -force -value 0x43C00018]
  set syn [expr {[mrd -force -value 0x43C0001C] & 0x1FFF}]
  set fl [expr {[mrd -force -value 0x43C00014] & 7}]
  cc; after 900; set d2 [expr {[mrd -force -value 0x43C00014] & 7}]
  puts [format "  inj_frame=0x%06X : capFAR=0x%06X syn=0x%04X flags=0x%X recheck=0x%X" $fr $far $syn $fl $d2]
}
