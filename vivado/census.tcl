connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
after 3000
set fh [open /tmp/census_frames.txt r]; set L {}
while {[gets $fh f] >= 0} { lappend L $f }
puts "CSV,far,col,minor,diff_words,verdict"
foreach F $L {
  set a [readframe $F]
  # stir the AXI path: a burst of reads, then read again
  for {set i 0} {$i<40} {incr i} { stat }
  set b [readframe $F]
  set d [framediff $a $b]
  puts [format "CSV,%s,%d,%d,%d,%s" $F [expr {($F>>7)&0x3FF}] [expr {$F&0x7F}] [llength $d] [expr {[llength $d] ? "DYNAMIC" : "static"}]]
}
