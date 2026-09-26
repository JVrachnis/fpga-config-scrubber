connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc capf {} { return [expr {[mrd -force -value 0x43C00014]&7}] }
proc far {} { return [mrd -force -value 0x43C00018] }
proc cc {} { mwr -force 0x43C0000C 0x10; after 3; mwr -force 0x43C0000C 0x0 }
proc inj {fr w m} { mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 40; mwr -force 0x43C0000C 0x1 }
inj 0x2000 0x0A 0x0; after 500; cc; after 200
set det 0; set cor 0; set tot 0; set fails {}
foreach col {0x2000 0x4000 0x6000 0x8000 0xA000 0xC000 0xE000 0x10000 0x14000 0x18000 0x1C000 0x20000} {
  foreach wd {0x0A 0x32} {
    cc; after 50; inj $col $wd 0x1; after 350
    set d [capf]; cc; after 850; set d2 [capf]; set f2 [far]
    incr tot; if {$d != 0} { incr det; if {$d2 == 0} { incr cor } else { lappend fails [format "0x%X/w%d" $col $wd] } }
  }
}
puts "RESULT total=$tot detected=$det corrected=$cor"
puts "PERSIST=$fails"
