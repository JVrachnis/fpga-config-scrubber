# =====================================================================
# Concurrency capacity: how many upsets "at once", and what "at once" means.
#
# With the scan running, two JTAG injections are ~100 ms apart - far longer than
# a sweep - so the first is always corrected before the second lands. Genuine
# concurrency therefore requires the scan-pause control: pause, plant every
# upset, resume. Everything present at resume is concurrent by construction.
#
# Cases (S = 2, group = column, subgroup = minor mod 2):
#   1  two frames, ADJACENT minors      -> different subgroups -> both correctable
#   2  two frames, minors differing by 2 -> SAME subgroup, SAME syndrome  -> the
#                                           algorithm's syndrome-match path
#   3  two frames, same subgroup, DIFFERENT syndromes -> the documented limit
#   4  three frames in one group (2 share a subgroup)
#   5  four frames, minors 0..3          -> two per subgroup
#   6  two frames in DIFFERENT columns   -> independent groups, both correctable
# =====================================================================
connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1500

proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }
proc pause {} { mwr -force 0x43C0000C 0x21; after 25 }
proc resume {} { mwr -force 0x43C0000C 0x1; after 25 }
proc inj_p {fr w m} {   ;# inject while already paused
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x21; after 4; mwr -force 0x43C0000C 0x27; after 60; mwr -force 0x43C0000C 0x21
}
proc hits {target ms} {
  set t [clock milliseconds]; set h 0
  while {[clock milliseconds]-$t < $ms} {
    cc; after 25
    if {[expr {[mrd -force -value 0x43C00014] & 2}]} {
      if {[expr {[mrd -force -value 0x43C00018] & 0xFFFFFF}] == $target} { incr h } } }
  return $h
}
# run one concurrent case: LIST = {{frame word mask} ...}
proc case {name LIST} {
  pause
  foreach v $LIST { lassign $v f w m; inj_p $f $w $m }
  resume
  after 600
  set verdict {}
  set nbad 0
  foreach v $LIST {
    lassign $v f w m
    set h [hits [expr {$f+2}] 400]
    if {$h == 0} { lappend verdict "ok" } else { lappend verdict "STUCK"; incr nbad }
  }
  puts [format "%-46s -> %s" $name [join $verdict " "]]
  # clean up anything left dirty (paused, so the scrubber cannot race us)
  if {$nbad} {
    pause
    foreach v $LIST {
      lassign $v f w m
      if {[hits [expr {$f+2}] 1] >= 0} { inj_p $f $w $m }
    }
    resume
    after 800
  }
  return $nbad
}

puts "=== concurrency capacity, S=2 (group = column, subgroup = minor mod 2) ==="
set C 0x001800    ;# a clean column to work in

case "1  two frames, minors 0,1  (different subgroups)" \
     [list [list [expr {$C+0}] 10 0x8] [list [expr {$C+1}] 20 0x10]]

case "2  two frames, minors 0,2  (same subgroup, SAME syndrome)" \
     [list [list [expr {$C+0}] 30 0x40] [list [expr {$C+2}] 30 0x40]]

case "3  two frames, minors 0,2  (same subgroup, DIFFERENT syndromes)" \
     [list [list [expr {$C+0}] 10 0x8] [list [expr {$C+2}] 60 0x40]]

case "4  three frames, minors 0,1,2 (two share a subgroup)" \
     [list [list [expr {$C+0}] 10 0x8] [list [expr {$C+1}] 20 0x10] [list [expr {$C+2}] 30 0x20]]

case "5  four frames, minors 0,1,2,3 (two per subgroup)" \
     [list [list [expr {$C+0}] 10 0x8] [list [expr {$C+1}] 20 0x10] \
           [list [expr {$C+2}] 30 0x20] [list [expr {$C+3}] 40 0x40]]

case "6  two frames in DIFFERENT columns (independent groups)" \
     [list [list 0x001800 10 0x8] [list 0x001A00 10 0x8]]

case "7  two frames, adjacent minors, both multi-bit (adj pairs)" \
     [list [list [expr {$C+0}] 15 0x300] [list [expr {$C+1}] 45 0xC00]]

puts "final init=[expr {([mrd -force -value 0x43C00010]>>16)&1}] scan=[expr {([mrd -force -value 0x43C00010]>>8)&0xFF}]"
