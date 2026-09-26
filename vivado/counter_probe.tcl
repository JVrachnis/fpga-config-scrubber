connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc dg {} { set d [expr {([mrd -force -value 0x43C00010] >> 16) & 0xFF}]
  return [format "init=%d start=%d done=%d wrtgl=%d" [expr {$d&1}] [expr {($d>>1)&7}] [expr {($d>>4)&7}] [expr {($d>>7)&1}]] }
proc doinj {fr w m} { mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1 }
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 500
puts "== baseline (background frames only), 10 samples over 3 s =="
for {set i 0} {$i < 10} {incr i} { puts "  [dg]"; after 300 }
puts "== inject 0x0A00 w10 b3, then 15 samples over 6 s =="
doinj 0x0A00 10 0x8
for {set i 0} {$i < 15} {incr i} { puts "  [dg]  syn=[format 0x%04X [expr {[mrd -force -value 0x43C0001C] & 0x1FFF}]] far=[format 0x%06X [expr {[mrd -force -value 0x43C00018] & 0xFFFFFF}]]"; after 400 }
