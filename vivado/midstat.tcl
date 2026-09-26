# Mid-correction injection: statistics + proof the decision logic really is frozen.
#
# Checks per trial:
#   scan counter (STATUS[15:8]) must NOT advance while frozen  -> scan driver stopped
#   parity_initialized (scrub_diag bit0) must survive          -> golden store intact
#   capture at the injected FAR after release                  -> the flip landed
connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1500

proc stat {} { return [mrd -force -value 0x43C00010] }
proc scanctr {} { return [expr {([stat]>>8)&0xFF}] }
proc init {} { return [expr {([stat]>>16)&1}] }
proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }
proc drain {} { for {set i 0} {$i<40} {incr i} { if {[mrd -force -value 0x43C00014]&2} { cc } else { break } } }

# inject one bit at FAR/word/mask with the given CTRL base held throughout
proc inject {base far word mask} {
  mwr -force 0x43C00000 $far; mwr -force 0x43C00004 $word; mwr -force 0x43C00008 $mask
  mwr -force 0x43C0000C $base; after 4
  mwr -force 0x43C0000C [expr {$base | 0x6}]; after 80
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

set frames {0x000600 0x000A00 0x000E00 0x001200 0x001600 0x001A00 0x001E00 0x002200
            0x002600 0x002A00 0x002E00 0x003200 0x003600 0x003A00 0x003E00 0x004200}
set words {12 20 33 47 55 61 74 88 5 27 40 52 66 79 91 18}

puts "trial mode        scan_frozen init_kept landed"
set res_f 0; set res_p 0; set nf 0; set np 0
set i 0
foreach F $frames W $words {
  incr i
  set frozen [expr {$i % 2}]           ;# alternate frozen / plain as a paired control
  drain
  if {$frozen} {
    set base 0x881                      ;# FREEZE_CLK | TEST_FREEZE | enable
    mwr -force 0x43C0000C $base; after 60
    set s0 [scanctr]
    inject $base $F $W 0x8
    after 100
    set s1 [scanctr]; set ik [init]
    mwr -force 0x43C0000C 0x1; after 200
    set sf [expr {$s0==$s1}]
    incr nf
  } else {
    set base 0x1
    set s0 [scanctr]
    inject $base $F $W 0x8
    set s1 [scanctr]; set ik [init]
    set sf "-"
    incr np
  }
  set n [watch [expr {$F+2}] 2000]
  set landed [expr {$n>0}]
  if {$landed} { if {$frozen} {incr res_f} else {incr res_p} }
  puts [format "%5d %-11s %-11s %-9s %s" $i [expr {$frozen?"FROZEN":"plain"}] $sf $ik $landed]
  # remove the upset the same way it was planted
  drain
  if {$frozen} {
    mwr -force 0x43C0000C 0x881; after 40; inject 0x881 $F $W 0x8; mwr -force 0x43C0000C 0x1
  } else {
    inject 0x1 $F $W 0x8
  }
  after 400; drain
}
puts ""
puts "FROZEN injections landed: $res_f / $nf"
puts "plain  injections landed: $res_p / $np"
puts "final init=[init]"
