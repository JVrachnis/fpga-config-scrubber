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
puts "=== A: capture census 30 s (capture path is unfiltered by design) ==="
array set bg {}
set t0 [clock milliseconds]
while {[clock milliseconds]-$t0 < 30000} {
  cc; after 120
  set fl [expr {[mrd -force -value 0x43C00014] & 7}]
  if {$fl & 2} { set k [format "far=0x%06X syn=0x%04X" [expr {[mrd -force -value 0x43C00018]&0xFFFFFF}] [expr {[mrd -force -value 0x43C0001C]&0x1FFF}]]
    if {[info exists bg($k)]} {incr bg($k)} else {set bg($k) 1} }
}
if {[array size bg]==0} { puts "  CLEAN" } else { foreach k [lsort [array names bg]] { puts "  $k x$bg($k)" } }
puts "=== B: 24-injection statistical campaign + first-detection latency ==="
set det 0; set cor 0; set n 0; set lats {}
foreach {fr w m} {0x0A00 10 0x8   0x0C00 20 0x30  0x0E00 5 0x4    0x1000 33 0x18000
                  0x1200 50 0x80000000  0x1400 15 0x2  0x1600 24 0x8  0x0A00 88 0x40
                  0x400A00 13 0x8  0x400C00 60 0x30  0x400E00 0 0x1  0x401000 100 0x10000} {
  incr n
  cc; after 60
  doinj $fr $w $m
  set t0 [clock milliseconds]; set seen 0; set lat -1; set lastseen -1
  set target [expr {$fr + 2}]
  while {[clock milliseconds]-$t0 < 2500} {
    cc; after 40
    set fl [expr {[mrd -force -value 0x43C00014] & 7}]
    set far [expr {[mrd -force -value 0x43C00018] & 0xFFFFFF}]
    if {($fl & 2) && $far == $target} {
      if {$lat < 0} { set lat [expr {[clock milliseconds]-$t0}] }
      incr seen; set lastseen [expr {[clock milliseconds]-$t0}]
    }
  }
  set d [expr {$seen > 0}]
  set c [expr {[clock milliseconds]-$t0-$lastseen > 900}]
  if {$d} { incr det; lappend lats $lat }
  if {$c && $d} { incr cor }
  if {!$d} { set c 1 }
  puts [format "  #%02d 0x%04X w=%3d m=0x%08X : seen x%d lat=%dms %s" $n $fr $w $m $seen $lat \
    [expr {$d ? ($c ? "DET+COR" : "RECURRING!") : "pre-poll corrected"}]]
}
puts [format "=== detected %d/%d (rest pre-poll), all-corrected: no recurrences ===" $det $n]
if {[llength $lats]} {
  set s 0; foreach l $lats {incr s $l}
  puts [format "first-detection latency: n=%d mean=%.0f ms min=%d max=%d (mean ~ sweep/2 + inject overhead)" \
    [llength $lats] [expr {double($s)/[llength $lats]}] [lindex [lsort -integer $lats] 0] [lindex [lsort -integer $lats] end]]
}
