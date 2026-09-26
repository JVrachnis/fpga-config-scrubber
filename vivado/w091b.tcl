# 0x00091B w12 b16: undetected on every configuration. Does the bit land?
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
after 2000
foreach v {{0x00091B 12 0x00010000} {0x00091B 12 0x00000008} {0x00091B 40 0x00000008} {0x00091A 12 0x00010000} {0x00091C 12 0x00010000} {0x000918 12 0x00010000}} {
  lassign $v F W M
  set base [readframe $F]
  drain; inject 0x1 $F $W $M
  set landed [framediff $base [readframe $F]]
  set h [first_hit [expr {$F+2}] 2500]
  after 300; set now [framediff $base [readframe $F]]
  puts [format "%-9s w%-3d %s  landed=%-16s first_ms=%5d  after=%s  %s" $F $W $M [expr {[llength $landed]?$landed:"NO"}] $h [expr {[llength $now]?$now:"clean"}] [recword]]
  if {[llength $now]} { inject 0x1 $F $W $M; after 200 }
  drain
}
