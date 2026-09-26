connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc capf {} { return [expr {[mrd -force -value 0x43C00014]&7}] }
proc cc {} { mwr -force 0x43C0000C 0x10; after 3; mwr -force 0x43C0000C 0x0 }
proc inj {fr w m} { mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 45; mwr -force 0x43C0000C 0x1 }
inj 0x2000 0x0A 0x0; after 500; cc; after 300
# canonical group-aligned FARs (minor=0), column-stepped by 0x80, within the scan range
set det 0; set cor 0; set tot 0; set w10fail 0; set w10tot 0
for {set c 0x1000} {$c <= 0x3000} {incr c 0x180} {
  foreach wd {0x05 0x0A 0x28} {
    cc; inj $c $wd 0x1; after 350; set d [capf]; cc; after 900; set d2 [capf]
    incr tot; if {$d!=0} { incr det; if {$d2==0} {incr cor} }
    if {$wd==0x0A} { incr w10tot; if {$d!=0 && $d2!=0} {incr w10fail} }
  }
}
puts "CANON total=$tot detected=$det corrected=$cor  (word10: $w10fail/$w10tot persisted)"
