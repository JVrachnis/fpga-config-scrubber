# Concurrent multi-frame capacity, measured with the new 32-bit counters rather
# than the capture register.
#
# The capture path is single-entry and sticky: a background event latches and
# blocks later captures until acked, so counting captures is a poor instrument.
# CTRL[10:8] selects what slv_reg7 returns:
#   1 us_timer   2 frames_ctr   3 det_ctr   4 cor_ctr   5 t_det   6 t_cor
# Corrections are counted at the source, so N staged upsets should produce
# exactly N corrections if all are corrected.
connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1500

# read instrumentation word `sel` WITHOUT disturbing the other CTRL bits.
# (An earlier version wrote 0x1|(sel<<8), which cleared the HOLD bit and
# silently released the freeze in the middle of staging.)
set ::CTRL 0x1
proc setctrl {v} { set ::CTRL $v; mwr -force 0x43C0000C $v; after 5 }
proc dbg {sel} {
  mwr -force 0x43C0000C [expr {$::CTRL | ($sel << 8)}]
  after 5
  set v [mrd -force -value 0x43C0001C]
  mwr -force 0x43C0000C $::CTRL
  return $v
}
proc hold_on  {} { setctrl 0x41; after 25 }
proc hold_off {} { setctrl 0x1;  after 25 }
proc inj_h {fr w m} {
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x41; after 4; mwr -force 0x43C0000C 0x47; after 60; mwr -force 0x43C0000C 0x41
}

puts "=== instrumentation sanity ==="
set t1 [dbg 1]; after 200; set t2 [dbg 1]
puts [format "us_timer:   %d -> %d  (delta %d us over ~200 ms + JTAG)" $t1 $t2 [expr {$t2-$t1}]]
set f1 [dbg 2]; after 200; set f2 [dbg 2]
puts [format "frames_ctr: %d -> %d  (delta %d frames)" $f1 $f2 [expr {$f2-$f1}]]
puts [format "det_ctr=%d cor_ctr=%d" [dbg 3] [dbg 4]]

# sweep period from the frame counter: 3251 frames per full device sweep
set fa [dbg 2]; set ta [dbg 1]; after 500; set fb [dbg 2]; set tb [dbg 1]
set df [expr {$fb-$fa}]; set dt [expr {$tb-$ta}]
if {$df > 0 && $dt > 0} {
  puts [format "frame rate: %d frames in %d us -> %.2f frames/ms; full sweep (3251 frames) = %.2f ms" \
        $df $dt [expr {1000.0*$df/$dt}] [expr {3251.0*$dt/$df/1000.0}]]
}

proc conc {name LIST} {
  set c0 [dbg 4]; set d0 [dbg 3]
  hold_on
  foreach v $LIST { lassign $v f w m; inj_h $f $w $m }
  set cH [dbg 4]
  hold_off
  after 1500
  set c1 [dbg 4]; set d1 [dbg 3]
  set n [llength $LIST]
  puts [format "%-52s staged=%d  detections=%d  corrections=%d  (during hold: %d)" \
        $name $n [expr {$d1-$d0}] [expr {$c1-$c0}] [expr {$cH-$c0}]]
  return [expr {$c1-$c0}]
}

set C 0x001800
puts "=== concurrent cases, corrections counted at the source ==="
conc "1  1 EVEN frame (baseline)"                  [list [list [expr {$C+0}] 10 0x300]]
conc "2  2 EVEN, different subgroups (minors 0,1)" [list [list [expr {$C+0}] 10 0x300] [list [expr {$C+1}] 50 0xC00]]
conc "3  2 EVEN, SAME subgroup (minors 0,2)"       [list [list [expr {$C+0}] 10 0x300] [list [expr {$C+2}] 50 0xC00]]
conc "4  4 ODD, same subgroup (minors 0,2,4,6)"    [list [list [expr {$C+0}] 10 0x8] [list [expr {$C+2}] 20 0x10] \
                                                          [list [expr {$C+4}] 30 0x20] [list [expr {$C+6}] 40 0x40]]
conc "5  8 ODD over 4 columns"                     [list [list 0x001800 10 0x8] [list 0x001801 20 0x8] \
                                                          [list 0x001880 30 0x8] [list 0x001881 40 0x8] \
                                                          [list 0x001900 50 0x8] [list 0x001901 60 0x8] \
                                                          [list 0x001980 70 0x8] [list 0x001981 80 0x8]]
puts "final init=[expr {([mrd -force -value 0x43C00010]>>16)&1}]"
