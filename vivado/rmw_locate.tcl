connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
after 3000
set fh [open /tmp/census_frames.txt r]; set L {}
while {[gets $fh f] >= 0} { lappend L $f }
array set dump {}
foreach F $L { set dump($F) [readframe $F] }
puts "reference dump: [llength $L] frames"
set A 0x400A23
set ref $dump($A)
set hits 0
for {set r 0} {$r < 12} {incr r} {
  if {![freeze]} { puts "freeze failed"; continue }
  set f1 [readframe $A 0x881]
  set f2 [readframe $A 0x881]
  thaw; after 100
  set d1 [llength [framediff $ref $f1]]; set d2 [llength [framediff $ref $f2]]
  set now [readframe $A]; set dn [llength [framediff $ref $now]]
  if {$d1 || $d2 || $dn} {
    incr hits
    # which reference frame does the bad buffer resemble most?
    set best ""; set bestscore -1
    foreach G $L { set score 0
      for {set w 0} {$w < 101} {incr w} { if {[lindex $dump($G) $w] == [lindex $f1 $w]} { incr score } }
      if {$score > $bestscore} { set bestscore $score; set best $G } }
    puts [format "rep %2d: first-read diff=%3d second-read diff=%3d frame-after diff=%3d   bad buffer matches %s in %d/101 words   %s" $r $d1 $d2 $dn $best $bestscore [recword]]
    # show a few bad words
    set ex {}; for {set w 0} {$w < 101 && [llength $ex] < 4} {incr w} { if {[lindex $ref $w] != [lindex $f1 $w]} { lappend ex [format "w%d ref=%08X got=%08X" $w [lindex $ref $w] [lindex $f1 $w]] } }
    puts "        $ex"
    if {$dn} { board_up; after 2000; set ref [readframe $A] }
  } else { puts "rep $r: clean" }
}
puts "corruptions: $hits / 12"
