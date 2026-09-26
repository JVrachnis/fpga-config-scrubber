connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc cc {} { mwr -force 0x43C0000C 0x10; after 3; mwr -force 0x43C0000C 0x0 }
proc doinj {fr w m} { mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1 }
doinj 0x2000 0x0A 0x0; after 600; cc; after 500
puts "=== does mask=0 create an error? does injection create an error at all? ==="
foreach m {0x0 0x1 0x0 0x1} {
  cc; after 200
  set base [expr {[mrd -force -value 0x43C00014]&7}]
  doinj 0x2000 10 $m; after 250
  set aft [expr {[mrd -force -value 0x43C00014]&7}]
  puts [format "  mask=0x%X : cap_before=0x%X cap_after=0x%X (%s)" $m $base $aft [expr {$aft!=0?{ERROR-CREATED}:{no-error}}]]
}
