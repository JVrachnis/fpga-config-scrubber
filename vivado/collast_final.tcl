connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }
proc doinj {fr w m} { mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1 }
proc watch {tag capfar ms} {
  set t0 [clock milliseconds]; set seen 0; set lastseen -1
  set dlat -1; set clat -1
  while {[clock milliseconds]-$t0 < $ms} {
    cc; after 150
    set fl [expr {[mrd -force -value 0x43C00014] & 7}]
    set far [expr {[mrd -force -value 0x43C00018] & 0xFFFFFF}]
    if {($fl & 2) && $far == $capfar} {
      incr seen; set lastseen [expr {[clock milliseconds]-$t0}]
      if {$dlat < 0} {
        set syn [mrd -force -value 0x43C0001C]
        set dlat [expr {($syn >> 13) & 0x7FFFF}]
        set clat [expr {(([mrd -force -value 0x43C00010] >> 24) & 0xFF) * 4}]
      }
    }
  }
  set quiet [expr {[clock milliseconds]-$t0-$lastseen}]
  puts [format "  %s: seen x%d, last +%dms, quiet %dms -> %s  (detect=%dus correct=%dus)" \
    $tag $seen $lastseen $quiet [expr {$seen==0 ? "never captured (pre-poll?)" : ($quiet>4000 ? "CORRECTED" : "STILL RECURRING")}] $dlat $clat]
}
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 600
puts "=== COL-LAST final validation (entry-group latch build) ==="
cc; after 150; doinj 0x0A23 10 0x8
watch "top    col-last 0x0A23" 0x0A81 15000
cc; after 150; doinj 0x400A23 3 0x4
watch "bottom col-last 0x400A23" 0x400A81 15000
cc; after 150; doinj 0x0C23 7 0x20
watch "top    col-last 0x0C23" 0x0C81 15000
puts "=== sanity: mid-column still fine ==="
cc; after 150; doinj 0x0A00 10 0x8
watch "mid 0x0A00" 0x0A02 8000
cc; after 150; doinj 0x400C00 60 0x30
watch "bottom mid 2b 0x400C00" 0x400C02 8000
