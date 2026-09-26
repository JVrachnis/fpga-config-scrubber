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
puts "=== POST-FIX: vary WORD (mask=0x1), expect syndrome to TRACK word ==="
foreach w {5 8 10 11 12 20 31 40 50} {
  cc; doinj 0x2000 $w 0x1; after 400
  set syn [expr {[mrd -force -value 0x43C0001C] & 0x1FFF}]
  set fl  [expr {[mrd -force -value 0x43C00014] & 7}]
  cc; after 700; set d2 [expr {[mrd -force -value 0x43C00014] & 7}]
  puts [format "  word=%2d : syn=0x%04X flags=0x%X recheck=0x%X" $w $syn $fl $d2]
}
puts "=== POST-FIX: vary BIT (word=10), expect syndrome to TRACK bit ==="
foreach m {0x1 0x2 0x4 0x8 0x10 0x100 0x10000 0x80000000} {
  cc; doinj 0x2000 10 $m; after 400
  set syn [expr {[mrd -force -value 0x43C0001C] & 0x1FFF}]
  set fl  [expr {[mrd -force -value 0x43C00014] & 7}]
  cc; after 700; set d2 [expr {[mrd -force -value 0x43C00014] & 7}]
  puts [format "  mask=0x%08X : syn=0x%04X flags=0x%X recheck=0x%X" $m $syn $fl $d2]
}
puts "=== POST-FIX: mask=0 should create NO error ==="
foreach t {1 2 3} {
  cc; after 200; set b [expr {[mrd -force -value 0x43C00014]&7}]
  doinj 0x2000 10 0x0; after 300
  set a [expr {[mrd -force -value 0x43C00014]&7}]
  puts [format "  trial %d mask=0 : before=0x%X after=0x%X (%s)" $t $b $a [expr {$a!=0?{STILL-CREATES-ERROR}:{clean-as-expected}}]]
}
