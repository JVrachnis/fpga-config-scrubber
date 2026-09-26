# =====================================================================
# Concurrent multi-frame upsets, staged with the new HOLD_CORRECTION test mode
# (CTRL bit 6). While held, Frame-ECC error flags are withheld from the syndrome
# handler, so nothing is detected or written back and upsets ACCUMULATE. On
# release every staged upset is present simultaneously - which is exactly what
# could not be arranged before (the injector's own ICAP read used to reveal each
# error and it was corrected within microseconds).
#
# Prediction under test (S = 2, group = column, subgroup = minor mod 2):
#   - ODD-multiplicity frames are located by the Frame-ECC syndrome alone and do
#     not consume the subgroup's vertical parity -> unlimited concurrently
#   - EVEN-multiplicity frames must be reconstructed from that parity
#     -> at most ONE per subgroup, i.e. two per column at S = 2
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
proc hold_on  {} { mwr -force 0x43C0000C 0x41; after 25 }   ;# bit6 | ready
proc hold_off {} { mwr -force 0x43C0000C 0x1;  after 25 }
proc inj_h {fr w m} {                     ;# inject while the corrector is frozen
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x41; after 4; mwr -force 0x43C0000C 0x47; after 60; mwr -force 0x43C0000C 0x41
}
proc hits {target ms} {
  set t [clock milliseconds]; set h 0
  while {[clock milliseconds]-$t < $ms} {
    cc; after 25
    if {[expr {[mrd -force -value 0x43C00014] & 2}]} {
      if {[expr {[mrd -force -value 0x43C00018] & 0xFFFFFF}] == $target} { incr h } } }
  return $h
}
# stage a set of upsets concurrently, release, then judge each
proc conc {name LIST} {
  hold_on
  foreach v $LIST { lassign $v f w m; inj_h $f $w $m }
  # sanity: while held, nothing may be corrected - the errors must still be there
  hold_off
  after 1200                                   ;# several sweeps
  set verdict {}; set bad 0
  foreach v $LIST {
    lassign $v f w m
    set h [hits [expr {$f+2}] 500]
    if {$h <= 2} { lappend verdict "ok" } else { lappend verdict "STUCK"; incr bad }
  }
  puts [format "%-56s -> %s" $name [join $verdict " "]]
  if {$bad} {                                   ;# restore, frozen so we cannot race
    hold_on
    foreach v $LIST { lassign $v f w m; inj_h $f $w $m }
    hold_off
    after 1200
    set left {}
    foreach v $LIST { lassign $v f w m; if {[hits [expr {$f+2}] 300] > 2} { lappend left [format 0x%06X $f] } }
    if {[llength $left]} { puts "        NOT CLEAN: $left" }
  }
  return $bad
}

# --- first: prove the freeze actually holds ----------------------------------
puts "=== 0: does HOLD_CORRECTION actually withhold correction? ==="
set F 0x001800
hold_on
inj_h $F 10 0x8
set seen [hits [expr {$F+2}] 600]
puts "0: captures while held = $seen   (expect 0 - detection is withheld)"
hold_off
after 800
set after_rel [hits [expr {$F+2}] 600]
puts "0: captures after release = $after_rel  (expect 1-2: detected once, corrected)"

set C 0x001800
puts "=== concurrent multi-frame cases (staged under freeze) ==="
conc "1  2 ODD frames, same subgroup (minors 0,2)" \
     [list [list [expr {$C+0}] 10 0x8] [list [expr {$C+2}] 60 0x40]]
conc "2  2 EVEN frames, different subgroups (minors 0,1)" \
     [list [list [expr {$C+0}] 10 0x300] [list [expr {$C+1}] 50 0xC00]]
conc "3  2 EVEN frames, SAME subgroup (minors 0,2)  <- predicted limit" \
     [list [list [expr {$C+0}] 10 0x300] [list [expr {$C+2}] 50 0xC00]]
conc "4  4 ODD frames, same subgroup (minors 0,2,4,6)" \
     [list [list [expr {$C+0}] 10 0x8] [list [expr {$C+2}] 20 0x10] \
           [list [expr {$C+4}] 30 0x20] [list [expr {$C+6}] 40 0x40]]
conc "5  1 EVEN + 3 ODD, same subgroup" \
     [list [list [expr {$C+0}] 10 0x300] [list [expr {$C+2}] 20 0x10] \
           [list [expr {$C+4}] 30 0x20] [list [expr {$C+6}] 40 0x40]]
conc "6  8 ODD frames spread over 4 columns" \
     [list [list 0x001800 10 0x8] [list 0x001801 20 0x8] [list 0x001880 30 0x8] [list 0x001881 40 0x8] \
           [list 0x001900 50 0x8] [list 0x001901 60 0x8] [list 0x001980 70 0x8] [list 0x001981 80 0x8]]
conc "7  2 EVEN frames per column, 2 columns (S=2 capacity)" \
     [list [list 0x001800 10 0x300] [list 0x001801 50 0xC00] \
           [list 0x001880 10 0x300] [list 0x001881 50 0xC00]]
puts "final init=[expr {([mrd -force -value 0x43C00010]>>16)&1}]"
