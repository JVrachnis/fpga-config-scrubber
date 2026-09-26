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
after 600

puts "=== A: detect-counter probe ==="
# A1: with capture held clear and NO error, pulse Start and sample det over time
cc; after 200
doinj 0x0A00 10 0x0
foreach d {50 150 400} {
  after $d
  set syn [mrd -force -value 0x43C0001C]
  puts [format "  +%dms after zero-mask Start: det=%d us (counter %s)" $d [expr {($syn>>13)&0x7FFFF}] \
    [expr {(($syn>>13)&0x7FFFF)==0x7FFFF ? "SATURATED" : "running/held"}]]
}
puts "=== B: col-last convergence, top (0x0A23), 30 s watch ==="
cc; after 150
doinj 0x0A23 10 0x8
set t0 [clock milliseconds]; set seen 0; set lastseen -1
while {[clock milliseconds]-$t0 < 30000} {
  cc; after 200
  set fl [expr {[mrd -force -value 0x43C00014] & 7}]
  set far [expr {[mrd -force -value 0x43C00018] & 0xFFFFFF}]
  if {($fl & 2) && $far == 0x0A81} { incr seen; set lastseen [expr {[clock milliseconds]-$t0}] }
}
puts [format "  top col-last: recurrences x%d, last seen +%d ms of 30000 -> %s" $seen $lastseen \
  [expr {$lastseen>=0 && ([clock milliseconds]-$t0-$lastseen)>3000 ? "converged" : ($seen==0?"never captured":"STILL RECURRING")}]]
puts "=== C: col-last convergence, bottom (0x400A23), 60 s watch ==="
cc; after 150
doinj 0x400A23 10 0x8
set t0 [clock milliseconds]; set seen 0; set lastseen -1
while {[clock milliseconds]-$t0 < 60000} {
  cc; after 200
  set fl [expr {[mrd -force -value 0x43C00014] & 7}]
  set far [expr {[mrd -force -value 0x43C00018] & 0xFFFFFF}]
  if {($fl & 2) && $far == 0x400A81} { incr seen; set lastseen [expr {[clock milliseconds]-$t0}] }
}
puts [format "  bottom col-last: recurrences x%d, last seen +%d ms of 60000 -> %s" $seen $lastseen \
  [expr {$lastseen>=0 && ([clock milliseconds]-$t0-$lastseen)>3000 ? "converged" : ($seen==0?"never captured":"STILL RECURRING")}]]
