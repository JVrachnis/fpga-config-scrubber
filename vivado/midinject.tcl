# Bit flip planted while the scrubber's state is FROZEN.
#
# The core's decision logic (parity calculator, syndrome handler, 2-D algorithm,
# scan driver) runs on a gated clock; the ICAP arbiter and controller run on the
# free-running clock. So with CTRL bit11 asserted the core's state stops exactly
# where it stands, while the configuration port remains usable by the injector.
#
#   CTRL bit 7  TEST_FREEZE : withdraw the scrubber's ICAP requests (combinational,
#                             so it works even with the core clock stopped)
#   CTRL bit 11 FREEZE_CLK  : stop the core clock - state held exactly
#   STATUS bit 4 ICAP_FREE  : no scrubber client holds the port
#   STATUS bit 5 ICAP_IDLE  : controller idle - a safe point to freeze at
connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1500
proc stat {} { return [mrd -force -value 0x43C00010] }
proc icap_free {} { return [expr {([stat]>>4)&1}] }
proc icap_idle {} { return [expr {([stat]>>5)&1}] }
proc frames {base} {
  mwr -force 0x43C0000C [expr {$base | (2<<8)}]; after 5
  set v [mrd -force -value 0x43C0001C]
  mwr -force 0x43C0000C $base; return $v
}
proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }
proc watch {target ms} {
  set t [clock milliseconds]; set n 0
  while {[clock milliseconds]-$t < $ms} {
    if {[expr {[mrd -force -value 0x43C00014] & 2}]} {
      if {[expr {[mrd -force -value 0x43C00018]&0xFFFFFF}] == $target} { incr n }
      cc
    }
    after 20
  }
  return $n
}

set F 0x001200
puts "=== state before freeze ==="
puts [format "icap_free=%d icap_idle=%d frames=%d" [icap_free] [icap_idle] [frames 0x1]]

# freeze: withdraw requests AND stop the core clock (0x881 = bit11|bit7|bit0)
puts "=== FREEZE (requests withdrawn + core clock stopped) ==="
mwr -force 0x43C0000C 0x881; after 100
set f1 [frames 0x881]
after 400
set f2 [frames 0x881]
puts [format "frames %d -> %d (delta %d, must be 0)  icap_free=%d icap_idle=%d" \
      $f1 $f2 [expr {$f2-$f1}] [icap_free] [icap_idle]]

# plant the upset while the core is frozen
puts "=== injecting while frozen ==="
mwr -force 0x43C00000 $F; mwr -force 0x43C00004 20; mwr -force 0x43C00008 0x8
mwr -force 0x43C0000C 0x881; after 4
mwr -force 0x43C0000C 0x887; after 80
mwr -force 0x43C0000C 0x881; after 40
puts [format "after injection while frozen: frames delta=%d (still 0 = core never moved)" \
      [expr {[frames 0x881]-$f2}]]

puts "=== RELEASE ==="
mwr -force 0x43C0000C 0x1; after 200
set n [watch [expr {$F+2}] 2500]
puts "captures at target after release: $n"
puts [format "frames now moving: %d" [expr {[frames 0x1]-$f2}]]
puts [format "init=%d" [expr {([stat]>>16)&1}]]
# clean up the same way
mwr -force 0x43C0000C 0x881; after 50
mwr -force 0x43C00000 $F; mwr -force 0x43C00004 20; mwr -force 0x43C00008 0x8
mwr -force 0x43C0000C 0x881; after 4
mwr -force 0x43C0000C 0x887; after 80
mwr -force 0x43C0000C 0x881; after 40
mwr -force 0x43C0000C 0x1; after 500
puts "cleanup done, init=[expr {([stat]>>16)&1}]"
