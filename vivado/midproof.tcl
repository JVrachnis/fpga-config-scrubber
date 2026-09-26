# Mid-correction injection: proof of freeze + large paired campaign.
#
# A: freeze with NO injection -> scan_counter must be static.  (scan_counter
#    counts SYNDROMEVALID edges in the AXI domain, so it only stands still if
#    nothing is driving the config port at all - which is exactly the state we
#    want before injecting.)
# B: freeze DURING a held correction episode (HOLD_CORRECTION staged first),
#    inject, release -> the flip must land and be corrected.
# C: 40 paired trials, frozen vs plain, for a landing rate.
connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1500

proc stat {} { return [mrd -force -value 0x43C00010] }
proc free {} { return [expr {([stat]>>4)&1}] }
proc sc {} { return [expr {([stat]>>8)&0xFF}] }
proc init {} { return [expr {([stat]>>16)&1}] }
proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }
proc drain {} { for {set i 0} {$i<40} {incr i} { if {[mrd -force -value 0x43C00014]&2} { cc } else { break } } }
proc wf {ms} { set t [clock milliseconds]
  while {[clock milliseconds]-$t < $ms} { if {[free]} { return 1 }; after 5 }; return 0 }
proc inject {base far word} {
  mwr -force 0x43C00000 $far; mwr -force 0x43C00004 $word; mwr -force 0x43C00008 0x8
  mwr -force 0x43C0000C $base; after 4
  mwr -force 0x43C0000C [expr {$base | 0x6}]; after 60
  mwr -force 0x43C0000C $base; after 40
}
proc watch {target ms} { set t [clock milliseconds]; set n 0
  while {[clock milliseconds]-$t < $ms} {
    if {[mrd -force -value 0x43C00014]&2} {
      if {[expr {[mrd -force -value 0x43C00018]&0xFFFFFF}] == $target} { incr n }; cc }
    after 15 }
  return $n }
proc freeze {} { mwr -force 0x43C0000C 0x81; set h [wf 500]
                 mwr -force 0x43C0000C 0x881; after 30; return $h }
proc thaw {} { mwr -force 0x43C0000C 0x1; after 150 }

puts "=== A. freeze holds the whole machine still (no injection) ==="
puts [format "running: sc=%d free=%d" [sc] [free]]
set h [freeze]
set a0 [sc]; after 400; set a1 [sc]; after 400; set a2 [sc]
puts [format "frozen:  handoff=%d sc %d -> %d -> %d  (deltas %d, %d - both must be 0)" \
      $h $a0 $a1 $a2 [expr {$a1-$a0}] [expr {$a2-$a1}]]
puts [format "         init=%d (golden store survived)" [init]]
thaw
set a3 [sc]; after 300; set a4 [sc]
puts [format "thawed:  sc %d -> %d (delta %d, must be > 0)" $a3 $a4 [expr {($a4-$a3+256)%256}]]

puts ""
puts "=== B. inject while a correction episode is held mid-flight ==="
drain
# stage: hold the corrector, plant an upset -> episode is detected but withheld
mwr -force 0x43C0000C 0x41
inject 0x41 0x002200 33
set staged [watch 0x2202 800]
puts "  staged upset detected under HOLD_CORRECTION: [expr {$staged>0}]"
# now freeze on top of the held episode and plant a SECOND upset in that frame
mwr -force 0x43C0000C 0xC1; wf 500; mwr -force 0x43C0000C 0x8C1; after 30
puts [format "  frozen mid-episode: free=%d init=%d" [free] [init]]
inject 0x8C1 0x002200 47
mwr -force 0x43C0000C 0x1; after 300
set n [watch 0x2202 2500]
puts "  after release: captures at frame = $n  init=[init]"
# clean both bits
drain
inject 0x1 0x002200 33; after 200; inject 0x1 0x002200 47; after 400; drain

puts ""
puts "=== C. 40 paired trials ==="
set rf 0; set rp 0; set nf 0; set np 0; set i 0
set base_far 0x000600
for {set k 0} {$k<40} {incr k} {
  incr i
  set F [expr {$base_far + ($k%20)*0x400}]
  set W [expr {(($k*17)%100)+1}]
  set frozen [expr {$i % 2}]
  drain
  if {$frozen} { incr nf; freeze; inject 0x881 $F $W; thaw } \
  else         { incr np; inject 0x1 $F $W }
  set n [watch [expr {$F+2}] 1500]
  if {$n>0} { if {$frozen} {incr rf} else {incr rp} }
  drain
  if {$frozen} { freeze; inject 0x881 $F $W; thaw } else { inject 0x1 $F $W }
  after 300; drain
}
puts ""
puts "FROZEN landed: $rf / $nf"
puts "plain  landed: $rp / $np"
puts "final init=[init]"
