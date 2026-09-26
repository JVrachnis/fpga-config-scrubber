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
puts "=== hardware-timed latency campaign (detect: CAP_SYN[31:13] us; correct: STATUS[31:24] x4us) ==="
set n 0; set det 0
set dets {}; set cors {}
foreach {fr w m tag} {
  0x0A00 10 0x8 mid        0x0C00 20 0x30 mid2b     0x0E00 5 0x4 mid
  0x1000 33 0x18000 mid2b  0x1200 50 0x80000000 mid 0x1400 15 0x2 mid
  0x0A23 10 0x8 COL-LAST   0x0C23 7 0x20 COL-LAST   0x1600 24 0x8 mid
  0x400A00 13 0x8 bottom   0x400C00 60 0x30 bot2b   0x400A23 3 0x4 BOT-COL-LAST
  0x0A00 88 0x40 mid       0x0C00 99 0x80000000 mid 0x0E00 0 0x1 w0
  0x1000 100 0x10000 w100  0x1200 27 0x6 mid2b      0x1400 55 0xC0000000 mid2b
} {
  incr n
  cc; after 100
  doinj $fr $w $m
  # wait for the capture (fast poll), then read hardware timers
  set t0 [clock milliseconds]; set got 0
  while {[clock milliseconds]-$t0 < 2500 && !$got} {
    after 15
    set fl [expr {[mrd -force -value 0x43C00014] & 7}]
    if {$fl & 2} { set got 1 }
  }
  if {$got} {
    set far [expr {[mrd -force -value 0x43C00018] & 0xFFFFFF}]
    set syn [expr {[mrd -force -value 0x43C0001C]}]
    set dlat [expr {($syn >> 13) & 0x7FFFF}]
    after 5
    set clat [expr {(([mrd -force -value 0x43C00010] >> 24) & 0xFF) * 4}]
    # verify corrected: ack and confirm silence under live scan
    cc; after 700
    set fl2 [expr {[mrd -force -value 0x43C00014] & 7}]
    set far2 [expr {[mrd -force -value 0x43C00018] & 0xFFFFFF}]
    set gone [expr {!($fl2 & 2) || $far2 != $far}]
    incr det; lappend dets $dlat; lappend cors $clat
    puts [format "  #%02d %-12s far=0x%06X: cap=0x%06X syn=0x%04X  detect=%6d us  correct=%4d us  %s" \
      $n $tag $fr $far [expr {$syn & 0x1FFF}] $dlat $clat [expr {$gone?"CORRECTED":"recurring?"}]]
  } else {
    puts [format "  #%02d %-12s far=0x%06X: no capture in 2.5 s (corrected before first poll or not landed)" $n $tag $fr]
    cc
  }
}
puts [format "=== %d/%d captured with hardware timing ===" $det $n]
if {[llength $dets]} {
  set s 0; foreach d $dets {incr s $d}
  set sc 0; foreach c $cors {incr sc $c}
  puts [format "detect latency: mean=%.0f us  min=%d  max=%d  (n=%d)" [expr {double($s)/[llength $dets]}] \
    [lindex [lsort -integer $dets] 0] [lindex [lsort -integer $dets] end] [llength $dets]]
  puts [format "correct latency: mean=%.0f us  min=%d  max=%d" [expr {double($sc)/[llength $cors]}] \
    [lindex [lsort -integer $cors] 0] [lindex [lsort -integer $cors] end]]
  puts "DETS: $dets"
  puts "CORS: $cors"
}
