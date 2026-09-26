# How often does an injection actually LAND?
#
# The campaign verdict "no recurring capture" is satisfied both by a corrected
# error and by an error that was never planted. The filtered-detection counter
# distinguishes them: a real upset in a valid frame must produce at least one
# filtered detection and one correction.
#
# Injects into distinct valid frames, one at a time, and reports the counter
# deltas per injection.
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
proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }

# compare three injection modes: live, scan-paused, corrector-frozen
proc trial {fr mode} {
  set d0 [dbg 6]
  switch $mode {
    live   { set base 0x1 }
    paused { set base 0x21 }
    frozen { set base 0x41 }
  }
  mwr -force 0x43C0000C $base; after 20
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 20; mwr -force 0x43C00008 0x8
  mwr -force 0x43C0000C $base; after 4
  mwr -force 0x43C0000C [expr {$base | 0x6}]; after 60
  mwr -force 0x43C0000C $base; after 20
  mwr -force 0x43C0000C 0x1                       ;# always release before observing
  after 1000
  set dd [expr {[dbg 6]-$d0}]
  # undo (same mode, so a failed plant stays failed rather than double-toggling)
  mwr -force 0x43C0000C $base; after 10
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 20; mwr -force 0x43C00008 0x8
  mwr -force 0x43C0000C $base; after 4
  mwr -force 0x43C0000C [expr {$base | 0x6}]; after 60
  mwr -force 0x43C0000C 0x1; after 600
  return $dd
}
set FR {0x000A00 0x000C00 0x000E00 0x001000 0x001200 0x001400 0x400A00 0x400C00 0x400E00 0x401000}
foreach mode {live paused frozen} {
  set land 0
  foreach fr $FR { if {[trial $fr $mode] > 0} { incr land } }
  puts "mode $mode : [llength $FR] injections, [set land] produced a filtered detection"
}
exit
set landed 0; set n 0
foreach fr {0x000A00 0x000A01 0x000A02 0x000C00 0x000C01 0x000E00 0x001000 0x001200
            0x400A00 0x400A01 0x400C00 0x400C01 0x400E00 0x401000 0x401200 0x401400} {
  incr n
  set d0 [dbg 6]; set c0 [dbg 7]
  cc
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 20; mwr -force 0x43C00008 0x8
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
  # observe for 1.2 s: captures (acking each poll) and the counters
  set seen 0
  set t0 [clock milliseconds]
  while {[clock milliseconds]-$t0 < 1200} {
    if {[expr {[mrd -force -value 0x43C00014] & 2}]} {
      if {[expr {[mrd -force -value 0x43C00018]&0xFFFFFF}] == [expr {$fr+2}]} { incr seen }
      cc
    }
    after 25
  }
  set dd [expr {[dbg 6]-$d0}]; set dc [expr {[dbg 7]-$c0}]
  if {$dd > 0} { incr landed }
  puts [format " %2d 0x%06X  0x00000008  %-8d  %-11d  %d" $n $fr $dd $dc $seen]
  # undo
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 20; mwr -force 0x43C00008 0x8
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
  after 400
}
puts "=== injections producing a filtered detection: $landed / $n ==="
