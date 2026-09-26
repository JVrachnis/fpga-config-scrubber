connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc capf {} { return [expr {[mrd -force -value 0x43C00014]&7}] }
proc far {} { return [mrd -force -value 0x43C00018] }
proc clearcap {} { mwr -force 0x43C0000C 0x10; after 3; mwr -force 0x43C0000C 0x0 }
proc inj {fr word mask} { mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $word; mwr -force 0x43C00008 $mask
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 40; mwr -force 0x43C0000C 0x1 }
inj 0x2000 0x0A 0x0; after 500; clearcap; after 200
set det 0; set cor 0; set tot 0
set fails {}
# sweep columns 0x2000..0x1E000 (step 0x2000) x a few word positions
for {set col 0x2000} {$col <= 0x1C000} {incr col 0x2000} {
  foreach wd {0x05 0x0A 0x28} {
    clearcap; after 60
    inj $col $wd 0x1
    after 350
    set d [capf]
    clearcap; after 900
    set d2 [capf]; set f2 [far]
    incr tot
    if {$d != 0} { incr det }
    if {$d != 0 && $d2 == 0} { incr cor } elseif {$d != 0 && $d2 != 0} { lappend fails [format "0x%05X/w%d(recheckFAR=0x%X)" $col $wd $f2] }
  }
}
puts "TOTAL=$tot  DETECTED=$det  CORRECTED=$cor"
puts "PERSIST_FAILS: $fails"
