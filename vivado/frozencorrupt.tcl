connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
after 3000
# 24 static frames spread over columns/minors, top half (no scrubber logic there)
set frames {}
foreach col {18 20 22 24 26 34 36 38 40 44 48 52} { foreach minor {2 33} { lappend frames [expr {($col<<7)|$minor}] } }
array set base {}
foreach F $frames { set base($F) [readframe $F] }
puts "=== A. one frozen readframe per hand-off, then plain verify ==="
set bad 0; set n 0
foreach F $frames { incr n
  freeze; set r [readframe $F 0x881]; thaw; after 100
  set v [readframe $F]; set d [llength [framediff $base($F) $v]]
  if {$d} { incr bad; puts [format "  CORRUPTED %s: %d words (frozen read itself showed %d diffs)" [format 0x%06X $F] $d [llength [framediff $base($F) $r]]]; board_up; after 2000; foreach G $frames { set base($G) [readframe $G] } }
}
puts "A: $bad / $n frozen ops corrupted the frame"
puts "=== B. same, but a throw-away read of a scratch frame first inside the freeze ==="
set bad 0; set n 0; set scratch 0x001B02
foreach F $frames { incr n
  freeze; readframe $scratch 0x881; set r [readframe $F 0x881]; thaw; after 100
  set v [readframe $F]; set d [llength [framediff $base($F) $v]]
  if {$d} { incr bad; puts [format "  CORRUPTED %s: %d words" [format 0x%06X $F] $d]; board_up; after 2000; foreach G $frames { set base($G) [readframe $G] } }
}
puts "B: $bad / $n corrupted with a scratch read first"
puts "=== C. plain ops only (control) ==="
set bad 0; set n 0
foreach F $frames { incr n; readframe $F; set v [readframe $F]; if {[llength [framediff $base($F) $v]]} { incr bad } }
puts "C: $bad / $n corrupted with plain ops"
