# Concurrent capacity, measured with source pulses. Each case uses its OWN
# column and undoes itself afterwards - injection is an XOR, so re-using a frame
# across cases silently toggles it clean and the case measures nothing.
connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1500

set ::CTRL 0x1
proc setctrl {v} { set ::CTRL $v; mwr -force 0x43C0000C $v; after 5 }
proc dbg {sel} {
  mwr -force 0x43C0000C [expr {$::CTRL | ($sel << 8)}]; after 5
  set v [mrd -force -value 0x43C0001C]
  mwr -force 0x43C0000C $::CTRL
  return $v
}
proc hold_on  {} { setctrl 0x41 }
proc hold_off {} { setctrl 0x1 }
proc inj {fr w m} {                    ;# inject at the current hold state
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C $::CTRL; after 4
  mwr -force 0x43C0000C [expr {$::CTRL | 0x6}]; after 60
  mwr -force 0x43C0000C $::CTRL
}
proc quiet_det {ms} {                  ;# detections during an idle window
  set a [dbg 3]; after $ms; set b [dbg 3]; return [expr {$b-$a}]
}

proc case {name LIST} {
  # 0. confirm we start from a clean device
  set pre [quiet_det 400]
  # 1. stage every upset with the corrector frozen
  hold_on
  foreach v $LIST { lassign $v f w m; inj $f $w $m }
  set dh [dbg 3]; set ch [dbg 4]
  # 2. release and let it work
  set d0 [dbg 3]; set c0 [dbg 4]; set t0 [dbg 1]
  hold_off
  after 1500
  set d1 [dbg 3]; set c1 [dbg 4]
  # 3. quiet window: anything still erroring keeps producing detections
  set resid [quiet_det 600]
  set n [llength $LIST]
  puts [format "%-46s staged=%d  det=%-3d cor=%-3d  residual_det=%-4d %s" \
        $name $n [expr {$d1-$d0}] [expr {$c1-$c0}] $resid \
        [expr {$resid > 3 ? "<-- NOT FULLY CORRECTED" : "all clear"}]]
  if {$pre > 3} { puts "        (warning: device was not clean before this case: $pre)" }
  # 4. undo, frozen, so the corrector cannot race the restore
  hold_on
  foreach v $LIST { lassign $v f w m; inj $f $w $m }
  hold_off
  after 1200
}

puts "=== concurrency capacity, pulse-counted (S=2) ==="
puts "frame rate check: [expr {[dbg 2]}] frames so far, timer [expr {[dbg 1]}] us"
case "1  1 EVEN frame (baseline)"                  [list [list 0x001800 10 0x300]]
case "2  2 EVEN, different subgroups"              [list [list 0x001880 10 0x300] [list 0x001881 50 0xC00]]
case "3  2 EVEN, SAME subgroup"                    [list [list 0x001900 10 0x300] [list 0x001902 50 0xC00]]
case "4  3 EVEN, SAME subgroup"                    [list [list 0x001980 10 0x300] [list 0x001982 40 0xC00] [list 0x001984 70 0x3000]]
case "5  4 ODD, same subgroup"                     [list [list 0x001A00 10 0x8] [list 0x001A02 20 0x10] \
                                                         [list 0x001A04 30 0x20] [list 0x001A06 40 0x40]]
case "6  1 EVEN + 3 ODD, same subgroup"            [list [list 0x001A80 10 0x300] [list 0x001A82 20 0x10] \
                                                         [list 0x001A84 30 0x20] [list 0x001A86 40 0x40]]
case "7  8 ODD over 4 columns"                     [list [list 0x001B00 10 0x8] [list 0x001B01 20 0x8] \
                                                         [list 0x001B80 30 0x8] [list 0x001B81 40 0x8] \
                                                         [list 0x001C00 50 0x8] [list 0x001C01 60 0x8] \
                                                         [list 0x001C80 70 0x8] [list 0x001C81 80 0x8]]
puts "final init=[expr {([mrd -force -value 0x43C00010]>>16)&1}]"
