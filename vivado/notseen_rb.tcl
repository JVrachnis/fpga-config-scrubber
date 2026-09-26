connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
after 3000
set fh [open /tmp/notseen.txt r]
puts "far       word bit  landed  after2.5s     nwords  healthy  verdict"
while {[gets $fh line] >= 0} {
  lassign $line far w b
  drain
  if {![freeze]} { puts "# scrubber unusable before trial - reprogram"; board_up; after 2000; freeze }
  set a [readframe $far 0x881]; thaw; after 50
  inject 0x1 $far $w [expr {1<<$b}]
  after 30
  if {![freeze]} { set c $a } else { set c [readframe $far 0x881]; thaw }
  set landed [expr {[llength [framediff $a $c]] > 0}]
  after 2500
  if {![freeze]} { set d {}; set nd -1 } else { set d [readframe $far 0x881]; thaw; after 50; set nd [llength [framediff $a $d]] }
  inject 0x1 0x001304 20 0x8; set h [expr {[first_hit 0x001306 1500] >= 0}]
  set v [expr {!$landed ? "not-landed" : ($nd == 0 ? "silently-corrected" : ($nd == 1 ? "left-uncorrected" : ($nd < 0 ? "dead" : "FRAME-OVERWRITTEN")))}]
  if {!$h} { append v "+dead" }
  puts [format "%-9s %-4d %-3d  %-7s %-13s %5d   %d        %s" $far $w $b [expr {$landed?"yes":"NO"}] [expr {$nd==0?"clean":($nd<0?"?":"differs")}] $nd $h $v]
  if {!$h} { puts "# re-programming"; board_up; after 2000 } elseif {$nd == 1} { inject 0x1 $far $w [expr {1<<$b}]; after 200 }
  drain
}
