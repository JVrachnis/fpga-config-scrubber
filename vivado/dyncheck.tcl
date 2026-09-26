connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
after 3000
foreach F {0x400A23 0x400D22 0x400BA3 0x001304 0x400988} {
  freeze; set a [readframe $F 0x881]; thaw; after 3000
  freeze; set b [readframe $F 0x881]; thaw; after 100
  set d [framediff $a $b]
  puts [format "%-9s two reads 3 s apart, no injection: %d words differ %s" $F [llength $d] [expr {[llength $d] ? "-> DYNAMIC content" : "-> static"}]]
}
