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
proc icap_free {} { return [expr {([mrd -force -value 0x43C00010] >> 4) & 1}] }
proc inj_frozen {fr w m} {
  mwr -force 0x43C0000C 0x81; after 30
  set g 0
  while {![icap_free] && $g < 100} { incr g; after 5 }
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x81; after 4
  mwr -force 0x43C0000C 0x87; after 60
  mwr -force 0x43C0000C 0x81; after 20
  mwr -force 0x43C0000C 0x1
}
set land 0; set n 0
foreach fr {0x000A00 0x000C00 0x000E00 0x001000 0x001200 0x001400 0x400A00 0x400C00} {
  incr n
  set d0 [dbg 6]; set c0 [dbg 7]
  inj_frozen $fr 20 0x8
  after 900
  set dd [expr {[dbg 6]-$d0}]; set dc [expr {[dbg 7]-$c0}]
  if {$dd > 0} { incr land }
  puts [format "  0x%06X : filt_det=%-3d corrections=%-3d %s" $fr $dd $dc [expr {$dd>0 ? "LANDED" : "no"}]]
  inj_frozen $fr 20 0x8
  after 700
}
puts "=== FROZEN protocol: $land / $n injections landed ==="
