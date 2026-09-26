connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc capf {} { return [expr {[mrd -force -value 0x43C00014]&7}] }
proc cc {} { mwr -force 0x43C0000C 0x10; after 3; mwr -force 0x43C0000C 0x0 }
proc inj {fr w m} { mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 40; mwr -force 0x43C0000C 0x1 }
inj 0x2000 0x0A 0x0; after 500; cc; after 200
foreach fr {0x2000 0x6000} {
  set line "frame 0x[format %X $fr]:"
  foreach w {0x00 0x05 0x0A 0x0F 0x14 0x32 0x63} {
    cc; after 50; inj $fr $w 0x1; after 350; set d [capf]; cc; after 700; set d2 [capf]
    set r [expr {$d==0 ? "?" : ($d2==0 ? "OK" : "PERSIST")}]
    append line [format " w%d=%s" $w $r]
  }
  puts $line
}
