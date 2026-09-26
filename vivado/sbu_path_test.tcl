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
after 500
puts "== two errors, same subgroup: inject 0x0A00(w10,b3) + 0x0A02(w20,b5) =="
doinj 0x0A00 10 0x8
after 300
doinj 0x0A02 20 0x20
array set seen {}
set t0 [clock milliseconds]
for {set i 0} {$i < 40} {incr i} {
  cc; after 450
  set fl [expr {[mrd -force -value 0x43C00014] & 7}]
  if {$fl & 2} {
    set far [expr {[mrd -force -value 0x43C00018] & 0xFFFFFF}]
    set syn [expr {[mrd -force -value 0x43C0001C] & 0x1FFF}]
    set k [format "far=0x%06X syn=0x%04X" $far $syn]
    if {![info exists seen($k)]} { set seen($k) 1
      puts [format "  +%5d ms first: %s" [expr {[clock milliseconds]-$t0}] $k]
    } else { incr seen($k) }
    set last($far) [clock milliseconds]
  }
}
puts "== last-seen per frame (ms since inject) =="
foreach f [lsort [array names last]] { puts [format "  far=0x%06X last seen +%d ms" $f [expr {$last($f)-$t0}]] }
puts "== capture histogram =="
foreach k [lsort [array names seen]] { puts "  $k x$seen($k)" }
