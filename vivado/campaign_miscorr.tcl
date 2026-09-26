# Honest campaign v2 (night run).  argv: [N] [tag]
# Adds to campaign_honest:
#   hw_det_us   Start -> capture, microseconds, from det_cnt (0x1C base layout [31:13])
#   hw_cor_us   capture -> correction done, from STATUS[31:24] x 4 us
#   exact       readback of the frame after correction is IDENTICAL to the
#               pre-injection readback (catches silent mis-corrections)
#   rejected    the injector guard refused the FAR (STATUS bits 6/7) - must be 0
# PASS = detected & corrected & clean & no watchdog & exact & not rejected
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
after 2000
source $::env(SCRUBBER_ROOT)/vivado/miscorr_vectors.tcl
set N [expr {[llength $argv] > 0 ? [lindex $argv 0] : 150}]
set TAG [expr {[llength $argv] > 1 ? [lindex $argv 1] : "v2"}]
proc detcnt {} { mwr -force 0x43C0000C 0x1; return [expr {([mrd -force -value 0x43C0001C] >> 13) & 0x7FFFF}] }
proc corus {} { return [expr {(([stat] >> 24) & 0xFF) * 4}] }
proc rejected {} { return [expr {([stat] >> 6) & 3}] }

puts "CSV,idx,far,word,mask,detected,first_ms,hw_det_us,hw_cor_us,rehits,init_ok,drops_d,wd_d,exact,rejected,PASS"
set pass 0; set det 0; set exact_n 0; set i 0; set failed {}
foreach v $VEC {
  incr i; if {$i > $N} break
  set F [lindex $v 0]; set W [lindex $v 1]; set M [lindex $v 2]
  set target [expr {$F + 2}]
  drain
  set base [readframe $F]
  set d0 [initdrops]; set w0 [wdpar]
  inject 0x1 $F $W $M
  set first [first_hit $target 2500]
  set detected [expr {$first >= 0}]
  set hwdet [detcnt]; set hwcor [corus]
  after 300
  set rehits [hits_in $target 800]
  set corrected [expr {$detected && $rehits <= 1}]
  set init_ok [init]; set dd [expr {([initdrops] - $d0) & 3}]; set wd [expr {[wdpar] != $w0}]
  set rej [rejected]
  set now [readframe $F]
  set exact [expr {[llength [framediff $base $now]] == 0}]
  set ok [expr {$detected && $corrected && $init_ok && $dd == 0 && !$wd && $exact && $rej == 0}]
  incr det $detected; incr exact_n $exact; incr pass $ok
  if {!$ok} { lappend failed [format "%s w%d %s det=%d rehits=%d exact=%d diff=%s rej=%d drops=%d wd=%d" $F $W $M $detected $rehits $exact [framediff $base $now] $rej $dd $wd] }
  puts [format "CSV,%d,%s,%d,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d" $i $F $W $M $detected $first $hwdet $hwcor $rehits $init_ok $dd $wd $exact $rej $ok]
  if {!$exact} { inject 0x1 $F $W $M; after 300 }
  drain
}
puts ""
puts "=== RESULT $TAG: $N injections  detected=$det  exact_restore=$exact_n  PASS=$pass ==="
foreach f $failed { puts "  FAIL $f" }
puts "final: [recword]"
