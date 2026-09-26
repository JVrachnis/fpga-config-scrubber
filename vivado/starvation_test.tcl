connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }
proc doinj {fr w m} { mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1 }
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 800
doinj 0x0A00 10 0x8
puts "injected w10 b3 at 0x0A00 (lands 0x0A02, syn should be 0x0488). Watching 60 s..."
set t0 [clock milliseconds]
set lastseen -1
for {set i 0} {$i < 120} {incr i} {
  cc; after 480
  set fl [expr {[mrd -force -value 0x43C00014] & 7}]
  set far [mrd -force -value 0x43C00018]
  set syn [expr {[mrd -force -value 0x43C0001C] & 0x1FFF}]
  if {($fl & 2) && $far == 0x0A02} { set lastseen [expr {[clock milliseconds]-$t0}] }
  if {$i % 20 == 0} { puts [format "  t=%5d ms cap far=0x%08X syn=0x%04X fl=0x%X (0x0A02 last seen +%d ms)" \
      [expr {[clock milliseconds]-$t0}] $far $syn $fl $lastseen] }
}
puts [format "FINAL: 0x0A02 error last observed at +%d ms of %d ms  -> %s" $lastseen [expr {[clock milliseconds]-$t0}] \
  [expr {$lastseen > 50000 ? "STILL PRESENT (correction broken/never runs for it)" : "DISAPPEARED (slow/starved correction works)"}]]
