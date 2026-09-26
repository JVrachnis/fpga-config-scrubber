# Mid-correction injection, with the ordered ICAP hand-off.
#
# Sequence per frozen trial:
#   1. CTRL bit7 (TEST_FREEZE)  -> hardware aborts the in-flight ICAP burst,
#      waits for the controller to park in SYNCED_S, then drops the scrubber's
#      arbiter requests.  STATUS bit4 (ICAP_FREE) rises only when both happened.
#   2. CTRL bit11 (FREEZE_CLK)  -> core clock gated; decision state frozen.
#   3. inject through the now-quiet port.
#   4. release both; the scrubber resumes from exactly where it stood.
connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1500

proc stat {} { return [mrd -force -value 0x43C00010] }
proc busy {} { return [expr {([stat]>>1)&1}] }
proc free {} { return [expr {([stat]>>4)&1}] }
proc scanctr {} { return [expr {([stat]>>8)&0xFF}] }
proc init {} { return [expr {([stat]>>16)&1}] }
proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }
proc drain {} { for {set i 0} {$i<40} {incr i} { if {[mrd -force -value 0x43C00014]&2} { cc } else { break } } }
proc wait_free {base ms} {
  set t [clock milliseconds]
  while {[clock milliseconds]-$t < $ms} { if {[free]} { return 1 }; after 5 }
  return 0
}
proc inject {base far word mask} {
  mwr -force 0x43C00000 $far; mwr -force 0x43C00004 $word; mwr -force 0x43C00008 $mask
  mwr -force 0x43C0000C $base; after 4
  mwr -force 0x43C0000C [expr {$base | 0x6}]; after 60
  mwr -force 0x43C0000C $base; after 40
}
proc watch {target ms} {
  set t [clock milliseconds]; set n 0
  while {[clock milliseconds]-$t < $ms} {
    if {[mrd -force -value 0x43C00014]&2} {
      if {[expr {[mrd -force -value 0x43C00018]&0xFFFFFF}] == $target} { incr n }
      cc
    }
    after 15
  }
  return $n
}

puts "=== step 1: does TEST_FREEZE now actually free the port? ==="
puts [format "running:  free=%d busy=%d" [free] [busy]]
mwr -force 0x43C0000C 0x81
set ok [wait_free 0x81 500]
puts [format "freeze:   free=%d busy=%d (handoff completed: %d)" [free] [busy] $ok]
mwr -force 0x43C0000C 0x1; after 200
puts [format "released: free=%d busy=%d" [free] [busy]]

puts ""
puts "=== step 2: paired frozen / plain injections ==="
set frames {0x000600 0x000A00 0x000E00 0x001200 0x001600 0x001A00 0x001E00 0x002200
            0x002600 0x002A00 0x002E00 0x003200 0x003600 0x003A00 0x003E00 0x004200
            0x004600 0x004A00 0x004E00 0x005200}
set words  {12 20 33 47 55 61 74 88 5 27 40 52 66 79 91 18 30 44 58 70}
puts "trial mode    handoff scan_frozen init landed"
set rf 0; set rp 0; set nf 0; set np 0; set i 0
foreach F $frames W $words {
  incr i
  set frozen [expr {$i % 2}]
  drain
  if {$frozen} {
    incr nf
    mwr -force 0x43C0000C 0x81
    set h [wait_free 0x81 500]
    mwr -force 0x43C0000C 0x881; after 30       ;# now stop the clock too
    set s0 [scanctr]
    inject 0x881 $F $W 0x8
    set s1 [scanctr]; set ik [init]
    set sf [expr {$s0==$s1}]
    mwr -force 0x43C0000C 0x1; after 150
  } else {
    incr np
    set h "-"; set sf "-"
    inject 0x1 $F $W 0x8
    set ik [init]
  }
  set n [watch [expr {$F+2}] 2000]
  if {$n>0} { if {$frozen} {incr rf} else {incr rp} }
  puts [format "%5d %-7s %-7s %-11s %-4s %s" $i [expr {$frozen?"FROZEN":"plain"}] $h $sf $ik [expr {$n>0}]]
  # undo the upset with an identical XOR injection
  drain
  if {$frozen} {
    mwr -force 0x43C0000C 0x81; wait_free 0x81 500; mwr -force 0x43C0000C 0x881; after 30
    inject 0x881 $F $W 0x8
    mwr -force 0x43C0000C 0x1
  } else {
    inject 0x1 $F $W 0x8
  }
  after 400; drain
}
puts ""
puts "FROZEN landed: $rf / $nf"
puts "plain  landed: $rp / $np"
puts "final init=[init] free=[free] busy=[busy]"
