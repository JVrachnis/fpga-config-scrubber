# Campaign with a verdict that cannot be granted to an upset nobody saw.
#
# Replaces big_campaign.tcl's `corrected = (hits2 <= 2)`, which the 2026-09-03
# review showed had produced "150/150 corrected" on a run whose own log says
# detected=2. Here a vector passes only if ALL of:
#   detected   first capture at FAR+2 within 2500 ms of Start
#   corrected  after a 300 ms settle, <= 1 further capture at FAR+2 in 800 ms
#              of free scanning (a persistent error re-captures every 3.3 ms)
#   clean      init stayed 1 and init_drops did not change (no golden re-learn,
#              which is the path that makes an injected bit permanently golden)
#   no-wd      wd_fires parity unchanged (the scrubber did not need a reset)
# Plain (unfrozen) injection: this measures the scrubber, not the freeze.
# Vectors: campaign_vectors_reachable.tcl - single-bit, injectable columns only.
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
source $::env(SCRUBBER_ROOT)/vivado/campaign_vectors_reachable.tcl
set N [expr {[llength $VEC] < 150 ? [llength $VEC] : 150}]
if {[llength $argv] > 0} { set N [lindex $argv 0] }

puts "CSV,idx,far,word,mask,detected,first_ms,rehits,init_ok,drops_d,wd_d,PASS"
set pass 0; set det 0; set cor 0; set clean 0; set i 0
set failed {}
foreach v $VEC {
  incr i; if {$i > $N} { break }
  set F [lindex $v 0]; set W [lindex $v 1]; set M [lindex $v 2]
  set target [expr {$F + 2}]
  drain
  set d0 [initdrops]; set w0 [wdpar]
  inject 0x1 $F $W $M
  set first [first_hit $target 2500]
  set detected [expr {$first >= 0}]
  after 300
  set rehits [hits_in $target 800]
  set corrected [expr {$detected && $rehits <= 1}]
  set init_ok [init]
  set dd [expr {([initdrops] - $d0) & 3}]
  set wd [expr {[wdpar] != $w0}]
  set isclean [expr {$init_ok && $dd == 0}]
  set ok [expr {$detected && $corrected && $isclean && !$wd}]
  incr det $detected; incr cor $corrected; incr clean $isclean; incr pass $ok
  if {!$ok} { lappend failed [format "%s w%d %s det=%d rehits=%d init=%d drops=%d wd=%d" $F $W $M $detected $rehits $init_ok $dd $wd] }
  puts [format "CSV,%d,%s,%d,%s,%d,%d,%d,%d,%d,%d,%d" $i $F $W $M $detected $first $rehits $init_ok $dd $wd $ok]
  if {!$detected} { puts "#   live: [livestr [live]]  sc=[sc] STATUS=[format 0x%08X [stat]]" }
  # if the frame is still dirty, do not carry it into the next trial
  if {$rehits > 1} { inject 0x1 $F $W $M; after 300 }
  drain
}
puts ""
puts "=== RESULT: $N injections  detected=$det  corrected=$cor  clean=$clean  PASS=$pass ==="
puts "failed vectors:"
foreach f $failed { puts "  $f" }
puts "final: [recword]"
