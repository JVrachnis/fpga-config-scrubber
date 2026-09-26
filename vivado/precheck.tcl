# Two pre-checks for the concurrency campaign.
#
# 1. Is a two-bit-in-one-word upset really invisible to the capture flag?
#    FINDINGS 12.1/13 claims it XOR-cancels the syndrome. The 7-series frame ECC
#    is a SECDED Hamming over the whole frame: two bits should give ECCERROR=1,
#    ECCERRORSINGLE=0 and a nonzero syndrome - i.e. VISIBLE, just not locatable.
#    The vectors that "proved" invisibility were in unreachable columns.
# 2. The 2-4 s tail on the last of N simultaneous upsets: time-resolved view of
#    what the core is doing after release (captures + STATUS/diag every ~15 ms).
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up

proc flags {} { return [expr {[capf] & 7}] }   ;# b0 crc b1 ecc b2 eccsingle

puts "=== 1. capture visibility by multiplicity (plain injection, reachable frame) ==="
puts "mask        kind      first_ms  flags(eccsingle,ecc,crc)  rehits  verdict"
foreach v {{0x00000008 single} {0x00000018 adj2} {0x00008080 sep2} {0x00000038 adj3} {0x0000F000 adj4}} {
  set M [lindex $v 0]; set kind [lindex $v 1]
  set F 0x001304; set target [expr {$F+2}]
  drain
  inject 0x1 $F 20 $M
  # capture the flags at the first hit
  set t [clock milliseconds]; set first -1; set fl "-"
  while {[clock milliseconds]-$t < 2500} {
    if {[capf]&2} {
      if {[capfar] == $target} { set first [expr {[clock milliseconds]-$t}]
        set f [flags]; set fl [format "%d,%d,%d" [expr {($f>>2)&1}] [expr {($f>>1)&1}] [expr {$f&1}]] }
      cc }
    if {$first >= 0} { break }
    after 8 }
  after 300; set re [hits_in $target 800]
  set verdict [expr {$first<0 ? "NOT SEEN" : ($re<=1 ? "corrected" : "DIRTY")}]
  puts [format "%-11s %-9s %6d    %-24s %3d     %s" $M $kind $first $fl $re $verdict]
  if {$re > 1} { inject 0x1 $F 20 $M; after 300 }
  drain
}

puts ""
puts "=== 2. the tail: N=4 released, timeline of captures + core status ==="
proc freeze_held {} { ctrl 0xC1; if {![wait_free 500]} { return 0 }; ctrl 0x8C1; after 20; return 1 }
set set_ {0x000A14 0x400B09 0x001919 0x000C08}
drain; ctrl 0x41; after 50
set w 20
foreach F $set_ { freeze_held; inject 0x8C1 $F $w 0x8; incr w 7; ctrl 0x41; after 60 }
puts "  held: [collect 800]"
drain
ctrl 0x1
set t0 [clock milliseconds]
puts "  ms     busy free idle  diag(scrub_diag[7:0])  captured"
set lastprint -100
while {[clock milliseconds]-$t0 < 5000} {
  set s [stat]; set t [expr {[clock milliseconds]-$t0}]
  set cap ""
  if {[capf]&2} { set cap [format 0x%06X [capfar]]; cc }
  if {$cap ne "" || $t-$lastprint >= 250} {
    puts [format "  %-6d %d    %d    %d     %08b               %s" $t [expr {($s>>1)&1}] [expr {($s>>4)&1}] [expr {($s>>5)&1}] [expr {($s>>16)&0xFF}] $cap]
    set lastprint $t }
  after 10 }
puts "final: [recword]"
