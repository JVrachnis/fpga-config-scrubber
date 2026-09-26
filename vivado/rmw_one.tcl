# one frozen readframe of $F after the ILA is armed; verdict to /tmp/rmw_result
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
select_arm
# do NOT reprogram (the ILA is live); just make sure the scrubber runs
ctrl 0x1
set F [lindex $argv 0]
set ref [readframe $F]
# wait for the ILA to be armed
for {set i 0} {$i < 600} {incr i} { if {[file exists /tmp/ila_armed]} break; after 100 }
file delete /tmp/ila_armed
if {![freeze]} { set out "freeze-failed" } else {
  set f1 [readframe $F 0x881]; thaw; after 100
  set now [readframe $F]
  set d1 [llength [framediff $ref $f1]]; set dn [llength [framediff $ref $now]]
  set out "read_diff=$d1 frame_diff=$dn"
  if {$dn} { set fh [open /tmp/rmw_bad_words w]; for {set w 0} {$w<101} {incr w} { puts $fh [format "%d %08X %08X" $w [lindex $ref $w] [lindex $f1 $w]] }; close $fh }
}
set fh [open /tmp/rmw_result w]; puts $fh $out; close $fh
puts "RESULT $out"
