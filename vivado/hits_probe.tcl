# Distinguish a genuinely uncorrected frame from a stale capture register.
#
# A frame that is still in error re-triggers a capture on EVERY sweep, so a
# 600 ms observation window with acks every 25 ms should see ~20+ hits.
# A frame that was corrected but whose capture was re-latched once (ack race)
# shows exactly one. The campaign scored "corrected" as hits==0, which
# conflates the two; this measures the actual distribution.
connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1500
source $::env(SCRUBBER_ROOT)/vivado/campaign_vectors.tcl

proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }
proc inj {fr w m} {
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
}
proc hits {target ms} {
  set t [clock milliseconds]; set h 0
  while {[clock milliseconds]-$t < $ms} {
    cc; after 25
    if {[expr {[mrd -force -value 0x43C00014] & 2}]} {
      if {[expr {[mrd -force -value 0x43C00018] & 0xFFFFFF}] == $target} { incr h } } }
  return $h
}
# first 60 vectors, recording the full hit count in the quiet window
puts "HITS,idx,kind,frame,quiet_hits,verdict"
set n 0; set zero 0; set one 0; set many 0
foreach v [lrange $VEC 0 59] {
  lassign $v fr w m kind
  incr n
  cc; after 40
  inj $fr $w $m
  after 500
  cc; after 40
  set h [hits [expr {$fr+2}] 600]
  if {$h == 0} { set vd "clean"; incr zero } elseif {$h <= 2} { set vd "STALE?"; incr one } else { set vd "DIRTY"; incr many }
  puts [format "HITS,%d,%s,0x%06X,%d,%s" $n $kind $fr $h $vd]
  if {$h > 2} { inj $fr $w $m; after 500 }
}
puts "=== quiet-window hit distribution over $n injections ==="
puts "  0 hits (clean):            $zero"
puts "  1-2 hits (stale capture):  $one"
puts "  >2 hits (really dirty):    $many"
