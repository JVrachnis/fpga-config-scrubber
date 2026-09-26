connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 800
proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }
set stuck 0; set okc 0
proc tryf {fr w m} {
  global stuck okc
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
  set t0 [clock milliseconds]; set n 0
  while {[clock milliseconds]-$t0 < 900} {
    cc; after 25
    if {[expr {[mrd -force -value 0x43C00014]&2}]} {
      if {[expr {[mrd -force -value 0x43C00018]&0xFFFFFF}] == $fr+2} { incr n } } }
  if {$n > 5} { incr stuck; puts [format "  0x%06X w=%d STUCK (caps=%d)" $fr $w $n]
    mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
    mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1; after 400
  } else { incr okc }
}
foreach f {0x0980 0x0A00 0x0A80 0x0B80 0x0C00 0x0D00 0x0E00 0x1000 0x1200 0x1400 0x1600 0x0200 0x0400 0x0600} {
  tryf $f 10 0x8
  tryf $f 55 0x1000
}
puts "=== STRESS RESULT: ok=$okc stuck=$stuck (28 injections, double per frame) ==="
