# 0x401405 w66 b3 in the prod build: det=1 rehits=36 exact=0, then every later
# injection undetected (03, 03b, 03c: 4/4).  What is the scrubber doing?
# argv: [F W M]  (default 0x401405 66 0x00000008)
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
after 2000
set F [expr {[llength $argv] > 0 ? [lindex $argv 0] : 0x401405}]
set W [expr {[llength $argv] > 1 ? [lindex $argv 1] : 66}]
set M [expr {[llength $argv] > 2 ? [lindex $argv 2] : 0x00000008}]
set T [expr {$F+2}]
proc dstr {d} { return [expr {[llength $d] ? $d : "clean"}] }
puts "# phase A: single injection, then watch 12 s"
puts "live0: [livestr [live]] [recword]"
set base [readframe $F]
drain
inject 0x1 $F $W $M
set landed [framediff $base [readframe $F]]
puts "landed=[dstr $landed]"
set h [first_hit $T 2500]
puts "first_ms=$h  det_cnt_us=[expr {([mrd -force -value 0x43C0001C] >> 13) & 0x7FFFF}] stat=[format 0x%08X [stat]]"
for {set k 0} {$k < 12} {incr k} {
  set n [hits_in $T 800]
  set d [framediff $base [readframe $F]]
  puts [format "t=%2ds hits/800ms=%2d  %s  %s  diff=%s" $k $n [livestr [live]] [recword] [dstr $d]]
}
puts "distinct FARs captured in 2 s: [collect 2000]"
puts "# phase B: control injection while the loop runs (vector 1 of the campaign list)"
foreach v {{0x401104 82 0x00004000} {0x40118F 56 0x00200000}} {
  lassign $v F2 W2 M2
  set b2 [readframe $F2]; drain; inject 0x1 $F2 $W2 $M2
  set h2 [first_hit [expr {$F2+2}] 2500]; after 300
  set r2 [hits_in [expr {$F2+2}] 800]; set d2 [framediff $b2 [readframe $F2]]
  puts [format "control %s w%d %s: first_ms=%d rehits=%d after=%s  %s" $F2 $W2 $M2 $h2 $r2 [dstr $d2] [livestr [live]]]
  if {[llength $d2]} { inject 0x1 $F2 $W2 $M2; after 200 }
  drain
}
puts "# phase C: soft reset (CTRL 1/7/1, no reprogram) - does the loop survive?"
ctrl 0x1; after 4; ctrl 0x7; after 60; ctrl 0x1; after 1500
drain
puts [format "after reset: hits/800ms=%d  %s  %s  diff=%s" [hits_in $T 800] [livestr [live]] [recword] [dstr [framediff $base [readframe $F]]]]
lassign {0x401104 82 0x00004000} F2 W2 M2
set b2 [readframe $F2]; drain; inject 0x1 $F2 $W2 $M2
set h2 [first_hit [expr {$F2+2}] 2500]; after 300
puts [format "control after reset %s w%d: first_ms=%d rehits=%d after=%s" $F2 $W2 $h2 [hits_in [expr {$F2+2}] 800] [dstr [framediff $b2 [readframe $F2]]]]
drain
puts "# phase D: neighbours, fresh board before each"
foreach v [list [list $F $W $M] [list $F $W 0x00000010] [list $F $W 0x00000004] [list $F 65 0x00000008] [list $F 67 0x00000008] [list $F 20 0x00000008] [list [expr {$F-1}] $W $M] [list [expr {$F+1}] $W $M] [list [expr {$F+0x80}] $W $M]] {
  lassign $v F3 W3 M3
  board_up; after 1500
  set b3 [readframe $F3]; drain; inject 0x1 $F3 $W3 $M3
  set l3 [framediff $b3 [readframe $F3]]
  set h3 [first_hit [expr {$F3+2}] 2500]; after 300
  set r3 [hits_in [expr {$F3+2}] 800]; set d3 [framediff $b3 [readframe $F3]]
  puts [format "NB %s w%-3d %s landed=%s first_ms=%5d rehits=%2d after=%s  %s" [format 0x%06X $F3] $W3 $M3 [dstr $l3] $h3 $r3 [dstr $d3] [livestr [live]]]
  drain
}
puts "=== LOOP401405 done ==="
