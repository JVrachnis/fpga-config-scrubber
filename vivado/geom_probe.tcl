# Geometry vs injectability  (review item 4)
#
# device_geometry_pkg says top cols 18-55 and bottom cols 0-55 are valid, with
# 36 minors each in cols 28-33. The injectable map says cols 28-33 (both
# halves) and bottom cols 0-17 never land. So for a frame the scrubber
# believes it scans, either
#   (a) the injector's write does not take,
#   (b) the frame has no ECC coverage (FRAME_ECCE2 silent), or
#   (c) the error is reported at a FAR other than +2.
# (c) is testable: thaw into HOLD (error persists) and collect EVERY captured
# FAR for 3 s, then look for anything within +-8 of the target.
#
# Also: where does the scan actually stop? Columns 56-64 with controls.
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up

proc probe {F} {
  drain
  if {![freeze]} { return "nofreeze" }
  inject 0x881 $F 20 0x8
  thaw 0x41
  set seen [collect 3000]
  ctrl 0x1; after 600; drain
  set near {}
  foreach s $seen { if {abs($s-$F) <= 8} { lappend near [format 0x%06X $s] } }
  return [expr {[llength $near] ? "near: $near" : "nothing within +-8 ([llength $seen] other FARs)"}]
}

puts "=== gap columns 28-33 (both halves) and bottom 0-17, HOLD + full collect ==="
foreach F {0x000E04 0x000F04 0x001004 0x001084 0x400E04 0x401004
           0x400004 0x400204 0x400404 0x400604 0x400804 0x400884} {
  set col [expr {($F>>7)&0x3FF}]; set half [expr {($F>>22)&1}]
  puts [format "  %-9s half=%d col=%-2d  %s" $F $half $col [probe $F]]
}

puts ""
puts "=== scan extent: columns 56..64, injected vs control ==="
puts "col  injected  control"
foreach col {56 57 58 59 60 61 62 63 64} {
  set F [expr {$col<<7}]
  drain; freeze; inject 0x881 $F 20 0x8; thaw
  set a [expr {[first_hit [expr {$F+2}] 2500] >= 0}]
  drain; freeze; after 73; thaw
  set c [expr {[first_hit [expr {$F+2}] 2500] >= 0}]
  puts [format "%-4d %d         %d" $col $a $c]
  drain
}
puts "final: [recword]"
