# =====================================================================
# The REAL capacity boundary.
#
# The first capacity run used single-bit upsets and everything passed - because
# an ODD-multiplicity error is located by the Frame-ECC syndrome alone and never
# touches the vertical parity. The scarce resource is the subgroup's parity, and
# only EVEN-multiplicity frames (where the Hamming word field XOR-cancels)
# consume it.
#
# Prediction: at most ONE even-multiplicity frame per SUBGROUP per sweep;
# odd-multiplicity frames are unlimited and independent.
#
#   A  2 even frames, SAME subgroup      -> expect failure (parity is shared)
#   B  2 even frames, DIFFERENT subgroups-> expect both corrected (S=2 capacity)
#   C  1 even + 1 odd, same subgroup     -> does the odd frame pollute the parity?
#   D  2 even frames, different columns  -> independent groups, both corrected
#   E  4 even frames, 2 per subgroup     -> expect failures
#   F  1 even + 3 odd, same subgroup     -> odd ones should not consume parity
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
proc inj_p {fr w m} {
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
proc case {name LIST} {
  pause
  foreach v $LIST { lassign $v f w m; inj_p $f $w $m }
  resume
  after 800                      ;# settle: several sweeps
  set verdict {}; set bad 0
  foreach v $LIST {
    lassign $v f w m
    set h [hits [expr {$f+2}] 500]
    if {$h <= 2} { lappend verdict "ok" } else { lappend verdict "STUCK($h)"; incr bad }
  }
  puts [format "%-52s -> %s" $name [join $verdict " "]]
  if {$bad} {                    ;# restore: re-XOR everything, paused
    pause
    foreach v $LIST { lassign $v f w m; inj_p $f $w $m }
    resume
    after 1000
    set left {}
    foreach v $LIST { lassign $v f w m; if {[hits [expr {$f+2}] 300] > 2} { lappend left [format 0x%06X $f] } }
    if {[llength $left]} { puts "        cleanup incomplete: $left" }
  }
  return $bad
}

puts "=== capacity boundary: EVEN-multiplicity frames compete for subgroup parity ==="
set C 0x001800
case "A  2 EVEN frames, minors 0,2  (SAME subgroup)" \
     [list [list [expr {$C+0}] 10 0x300] [list [expr {$C+2}] 50 0xC00]]
case "B  2 EVEN frames, minors 0,1  (different subgroups)" \
     [list [list [expr {$C+0}] 10 0x300] [list [expr {$C+1}] 50 0xC00]]
case "C  1 EVEN + 1 ODD, minors 0,2  (same subgroup)" \
     [list [list [expr {$C+0}] 10 0x300] [list [expr {$C+2}] 50 0x40]]
case "D  2 EVEN frames, different columns" \
     [list [list 0x001800 10 0x300] [list 0x001A00 10 0x300]]
case "E  4 EVEN frames, minors 0,1,2,3 (2 per subgroup)" \
     [list [list [expr {$C+0}] 10 0x300] [list [expr {$C+1}] 20 0x300] \
           [list [expr {$C+2}] 30 0x300] [list [expr {$C+3}] 40 0x300]]
case "F  1 EVEN + 3 ODD, minors 0,2,4,6 (same subgroup)" \
     [list [list [expr {$C+0}] 10 0x300] [list [expr {$C+2}] 20 0x40] \
           [list [expr {$C+4}] 30 0x40] [list [expr {$C+6}] 40 0x40]]
puts "final init=[expr {([mrd -force -value 0x43C00010]>>16)&1}]"
