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
# track a specific frame's error: watch captures for its FAR; corrected == stops recurring
proc watch {tag far_expect timeout_ms} {
  set t0 [clock milliseconds]; set lastseen -1; set seen 0
  while {[clock milliseconds] - $t0 < $timeout_ms} {
    cc; after 300
    set fl [expr {[mrd -force -value 0x43C00014] & 7}]
    set far [expr {[mrd -force -value 0x43C00018] & 0xFFFFFF}]
    if {($fl & 2) && $far == $far_expect} { set lastseen [expr {[clock milliseconds]-$t0}]; incr seen }
  }
  set total [expr {[clock milliseconds]-$t0}]
  if {$seen == 0} { puts "  $tag: NEVER captured (missed or corrected before first poll)" 
  } elseif {$total - $lastseen > 2000} { puts [format "  %s: detected (x%d), last seen +%d ms of %d -> CORRECTED" $tag $seen $lastseen $total]
  } else { puts [format "  %s: STILL RECURRING at +%d ms of %d (x%d) -> NOT corrected" $tag $lastseen $total $seen] }
}
puts "=== T1: single bit @0x0A00 w10 b3 (lands 0x0A02) ==="
doinj 0x0A00 10 0x8
watch "single-bit 0x0A02" 0x0A02 8000
puts "=== T2: ADJACENT DOUBLE BIT @0x0C00 w20 bits4-5 (lands 0x0C02) - THE 2-D CASE ==="
doinj 0x0C00 20 0x30
watch "double-bit 0x0C02" 0x0C02 8000
puts "=== T3: mini campaign: 5 more single-bit injections, different frames ==="
set ok 0
foreach {fr lf} {0x0E00 0x0E02  0x1000 0x1002  0x1200 0x1202  0x1400 0x1402  0x1600 0x1602} {
  doinj $fr 15 0x4
  set t0 [clock milliseconds]; set lastseen -1; set seen 0
  while {[clock milliseconds] - $t0 < 5000} {
    cc; after 250
    set fl [expr {[mrd -force -value 0x43C00014] & 7}]
    set far [expr {[mrd -force -value 0x43C00018] & 0xFFFFFF}]
    if {($fl & 2) && $far == $lf} { set lastseen [expr {[clock milliseconds]-$t0}]; incr seen }
  }
  set corrected [expr {$seen > 0 && ([clock milliseconds]-$t0-$lastseen) > 1500}]
  if {$corrected} { incr ok }
  puts [format "  far=0x%04X: seen x%d last=+%dms %s" $lf $seen $lastseen [expr {$corrected?"CORRECTED":"?"}]]
}
puts [format "=== campaign: %d/5 detected+corrected with live-scan verification ===" $ok]
puts [format "final diag=0x%02X" [expr {([mrd -force -value 0x43C00010]>>16)&0xFF}]]
