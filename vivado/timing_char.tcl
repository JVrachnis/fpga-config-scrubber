# =====================================================================
# Timing characterisation: init, sweep, detect, correct, turnaround.
#
# JTAG is the instrument and it is slow (~0.2-1 ms per register access), so
# every measurement here either (a) is bounded well above the JTAG floor, or
# (b) uses a differential method that cancels the constant JTAG offset.
# The JTAG floor itself is measured first so every later number can be read
# in context.
# =====================================================================
connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl

proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }
proc st {} { return [mrd -force -value 0x43C00010] }
proc scan_ctr {} { return [expr {([st] >> 8) & 0xFF}] }
proc init_ok {} { return [expr {([st] >> 16) & 1}] }

# ---------- 0: JTAG floor ----------------------------------------------------
puts "=== 0: JTAG access latency (the instrument's own floor) ==="
set t0 [clock milliseconds]
for {set i 0} {$i < 200} {incr i} { st }
set jt [expr {([clock milliseconds]-$t0)/200.0}]
puts [format "0: single register read = %.3f ms  (200 reads in %d ms)" $jt [expr {[clock milliseconds]-$t0}]]

# ---------- 1: golden initialisation time ------------------------------------
puts "=== 1: golden-parity initialisation (full-device read) x5 ==="
set inits {}
for {set r 0} {$r < 5} {incr r} {
  fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
  ps7_init; ps7_post_config
  mwr -force 0xF8007000 0x4600E07F
  set t0 [clock milliseconds]
  mwr -force 0x43C0000C 0x1; mwr -force 0x43C0000C 0x7
  set n 0
  while {[clock milliseconds]-$t0 < 3000} { incr n; if {[init_ok]} break }
  set el [expr {[clock milliseconds]-$t0}]
  lappend inits $el
  puts [format "1:   run %d: init asserted after %d ms (%d polls, i.e. <= %d ms of JTAG overhead)" \
        [expr {$r+1}] $el $n [expr {int($n*$jt)}]]
  mwr -force 0x43C0000C 0x1
  after 300
}
puts "1: NOTE - this is an UPPER BOUND: the poll loop cannot see the bit sooner than one JTAG read."

# ---------- 2: scan pass rate (differential, cancels JTAG offset) -------------
# The 8-bit scan counter wraps every 256 passes, far faster than JTAG can track,
# so absolute counting is impossible. Instead: read, wait D ms, read; the delta
# mod 256 is valid as long as fewer than 256 passes elapse. Sweeping D and
# fitting the slope removes the constant JTAG cost.
puts "=== 2: scan pass rate (delta-counter, swept dwell) ==="
foreach D {1 2 4 8 16} {
  set tot 0; set reps 20
  for {set i 0} {$i < $reps} {incr i} {
    set a [scan_ctr]; after $D; set b [scan_ctr]
    incr tot [expr {($b - $a) & 0xFF}]
  }
  set avg [expr {$tot/double($reps)}]
  puts [format "2:   dwell %2d ms -> %6.2f passes   (%.1f passes/ms)" $D $avg [expr {$avg/$D}]]
}
puts "2: slope (passes/ms) between the larger dwells is the true rate; the intercept is JTAG cost."

# ---------- 3: correction latency (hardware counter) -------------------------
puts "=== 3: correction latency, hardware us counter, 20 injections ==="
set lats {}
foreach fr {0x000C00 0x000E00 0x001000 0x001200 0x001400 0x001600 0x400C00 0x400E00 0x401000 0x401200} {
  foreach w {10 55} {
    cc; after 40
    mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 0x8
    mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
    after 200
    set l [expr {(([st] >> 24) & 0xFF) * 4}]
    lappend lats $l
  }
}
puts "3: samples (us): $lats"
set sum 0; set mn 9999; set mx 0
foreach l $lats { incr sum $l; if {$l<$mn} {set mn $l}; if {$l>$mx} {set mx $l} }
puts [format "3: n=%d mean=%.1f us  min=%d  max=%d" [llength $lats] [expr {$sum/double([llength $lats])}] $mn $mx]

# ---------- 4: coincidence window -------------------------------------------
# Two upsets count as "simultaneous" if both are still present when the group's
# compare pass runs. Scan-pause lets us place two upsets with a controlled gap:
#   pause -> inject A -> resume for D ms -> pause -> inject B -> resume
# D = 0 makes them genuinely concurrent; large D lets A be corrected first.
# Both land in the SAME subgroup with DIFFERENT syndromes - the case the 2-D
# code cannot resolve concurrently - so the crossover D is the window.
puts "=== 4: coincidence window (same subgroup, different syndromes) ==="
proc inj {fr w m} {
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
}
proc quiet {target ms} {
  set t [clock milliseconds]; set h 0
  while {[clock milliseconds]-$t < $ms} {
    cc; after 25
    if {[expr {[mrd -force -value 0x43C00014] & 2}]} {
      if {[expr {[mrd -force -value 0x43C00018] & 0xFFFFFF}] == $target} { incr h } } }
  return $h
}
foreach D {0 1 2 4 8 16 32} {
  set A 0x001800; set B 0x001802     ;# same column, minors 0 and 2 -> same subgroup at S=2
  mwr -force 0x43C0000C 0x21         ;# pause scan
  after 20
  inj $A 10 0x8
  if {$D > 0} { mwr -force 0x43C0000C 0x1; after $D; mwr -force 0x43C0000C 0x21; after 5 }
  inj $B 60 0x40                     ;# different word AND bit -> different syndrome
  mwr -force 0x43C0000C 0x1          ;# resume
  after 400
  set hA [quiet [expr {$A+2}] 500]
  set hB [quiet [expr {$B+2}] 500]
  puts [format "4:   gap %2d ms -> A %s , B %s" $D [expr {$hA==0 ? "corrected" : "STUCK"}] [expr {$hB==0 ? "corrected" : "STUCK"}]]
  # clean up whatever survived
  if {$hA} { inj $A 10 0x8; after 400 }
  if {$hB} { inj $B 60 0x40; after 400 }
  after 200
}
puts "final: init=[init_ok]"
