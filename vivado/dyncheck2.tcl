connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
after 3000
foreach F {0x001304 0x400D22 0x400BA3 0x400A23} {
  set a [readframe $F]; after 500; set b [readframe $F]
  puts [format "%-9s plain,plain      : %d words differ" $F [llength [framediff $a $b]]]
  freeze; set c [readframe $F 0x881]; thaw; after 300
  puts [format "%-9s plain vs frozen  : %d words differ" $F [llength [framediff $a $c]]]
  set d [readframe $F]
  puts [format "%-9s plain after frozen: %d words differ from first plain %s" $F [llength [framediff $a $d]] [expr {[llength [framediff $a $d]] ? "<- the frozen op CHANGED the frame" : ""}]]
  puts "   [recword]"
}
