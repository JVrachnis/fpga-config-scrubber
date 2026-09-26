connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1500
proc dbg {sel} {
  mwr -force 0x43C0000C [expr {0x1 | ($sel<<8)}]; after 5
  set v [mrd -force -value 0x43C0001C]
  mwr -force 0x43C0000C 0x1; return $v
}
proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }
puts "fresh device: det=[dbg 3] cor=[dbg 4]"
mwr -force 0x43C00000 0x001800; mwr -force 0x43C00004 10; mwr -force 0x43C00008 0x8
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
# watch BOTH the capture path and the counters
for {set i 0} {$i < 12} {incr i} {
  set cap 0; set far 0
  if {[expr {[mrd -force -value 0x43C00014] & 2}]} {
    set cap 1; set far [expr {[mrd -force -value 0x43C00018] & 0xFFFFFF}] }
  puts [format "  t=%2d  capture=%d far=0x%06X   det=%d cor=%d" $i $cap $far [dbg 3] [dbg 4]]
  if {$cap} { cc }
  after 100
}
