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
puts "=== A: clean-boot capture census, 8 s (background flood check) ==="
array set bg {}
for {set i 0} {$i < 40} {incr i} {
  cc; after 180
  set fl [expr {[mrd -force -value 0x43C00014] & 7}]
  if {$fl & 2} { set k [format "far=0x%06X syn=0x%04X" [expr {[mrd -force -value 0x43C00018]&0xFFFFFF}] [expr {[mrd -force -value 0x43C0001C]&0x1FFF}]]
    if {[info exists bg($k)]} {incr bg($k)} else {set bg($k) 1} }
}
if {[array size bg]==0} { puts "  CLEAN - no background captures" } else {
  foreach k [lsort [array names bg]] { puts "  $k x$bg($k)" } }
puts "=== B: 12-injection campaign (fast polls: detect once, then absent) ==="
set det 0; set cor 0; set n 0
foreach {fr w m} {0x0A00 10 0x8  0x0C00 20 0x30  0x0E00 5 0x4  0x1000 33 0x18000  0x1200 50 0x80000000  0x1400 15 0x2
                  0x1600 24 0x8  0x0A00 7 0x100  0x0C00 60 0x1  0x0E00 42 0x30  0x1000 11 0x800  0x1200 3 0x10} {
  incr n
  cc; after 100
  doinj $fr $w $m
  set seen 0; set lastseen -1; set t0 [clock milliseconds]
  set target [expr {$fr + 2}]
  while {[clock milliseconds]-$t0 < 3500} {
    cc; after 120
    set fl [expr {[mrd -force -value 0x43C00014] & 7}]
    set far [expr {[mrd -force -value 0x43C00018] & 0xFFFFFF}]
    if {($fl & 2) && $far == $target} { incr seen; set lastseen [expr {[clock milliseconds]-$t0}] }
  }
  set d [expr {$seen > 0}]
  set c [expr {$d && ([clock milliseconds]-$t0-$lastseen) > 1200}]
  if {$d} {incr det}; if {$c} {incr cor}
  puts [format "  #%02d far=0x%04X w=%2d m=0x%08X : seen x%d last=+%4dms  %s" $n $fr $w $m $seen $lastseen \
    [expr {$c ? "DETECTED+CORRECTED" : ($d ? "detected, recurring?" : "not seen (corrected pre-poll?)")}]]
}
puts [format "=== CAMPAIGN: %d/%d observed-detected, %d/%d verified-corrected (unobserved = faster than 120ms poll) ===" $det $n $cor $n]
puts [format "final diag=0x%02X, scan alive: %d->%d" [expr {([mrd -force -value 0x43C00010]>>16)&0xFF}] \
  [expr {([mrd -force -value 0x43C00010]>>8)&0xFF}] [expr {[after 300; ([mrd -force -value 0x43C00010]>>8)&0xFF}]]
