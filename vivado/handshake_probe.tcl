connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc doinj {fr w m} { mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1 }
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 800
puts "== inject single bit at 0x0A00 w10 b3, then sample diag/pcalc fast =="
doinj 0x0A00 10 0x8
array set seen {}
set t0 [clock milliseconds]
for {set i 0} {$i < 400} {incr i} {
  set d [expr {([mrd -force -value 0x43C00010] >> 16) & 0xFF}]
  set p [expr {([mrd -force -value 0x43C00014] >> 24) & 0xFF}]
  set k [format "diag=0x%02X pcalc=0x%02X" $d $p]
  if {[info exists seen($k)]} { incr seen($k) } else { set seen($k) 1
    puts [format "  +%4d ms NEW state: %s" [expr {[clock milliseconds]-$t0}] $k] }
}
puts "== histogram =="
foreach k [lsort [array names seen]] { puts "  $k  x$seen($k)" }
set syn [expr {[mrd -force -value 0x43C0001C] & 0x1FFF}]
set far [mrd -force -value 0x43C00018]
puts [format "capture now: far=0x%08X syn=0x%04X (persisting=%s)" $far $syn [expr {$syn!=0?"YES":"no"}]]
