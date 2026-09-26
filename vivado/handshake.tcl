# Does the injector's busy/synced handshake explain the ~25% landing rate?
#
# The 2021 PS application (rtl/modules/injection_PS/src/helloworld.c) always
# calls FI_Wait_until_ready() - poll STATUS bit1 (Busy) - before issuing an
# injection, and checks bit0 (synced). Every xsdb script written in 2026 skips
# both: it writes the registers, pulses Start, waits a fixed 60 ms and moves on.
# If the injector is busy or not synced at that moment the Start is simply lost.
#
# Compares three protocols, counting FILTERED detections (CTRL[10:8]=6), which
# only a genuinely planted upset in valid space can produce.
connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1500

proc dbg {sel} {
  mwr -force 0x43C0000C [expr {0x1 | ($sel<<8)}]; after 5
  set v [mrd -force -value 0x43C0001C]
  mwr -force 0x43C0000C 0x1; return $v
}
proc st     {} { return [mrd -force -value 0x43C00010] }
proc busy   {} { return [expr {([st] >> 1) & 1}] }
proc synced {} { return [expr {[st] & 1}] }

# --- protocol A: what every 2026 xsdb script does
proc inj_naive {fr w m} {
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
}
# --- protocol B: the 2021 PS handshake - wait !busy before AND after
proc inj_hs {fr w m} {
  set g 0
  while {[busy] && $g < 200} { incr g; after 5 }
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x7
  set g 0
  while {![busy] && $g < 100} { incr g; after 2 }   ;# wait for it to actually start
  set g 0
  while {[busy]  && $g < 400} { incr g; after 5 }   ;# and to finish
  mwr -force 0x43C0000C 0x1
}
# --- protocol C: handshake + require synced first
proc inj_hs_sync {fr w m} {
  set g 0
  while {![synced] && $g < 200} { incr g; mwr -force 0x43C0000C 0x3; after 5 }
  inj_hs $fr $w $m
}

set FR {0x000A00 0x000C00 0x000E00 0x001000 0x001200 0x001400 0x400A00 0x400C00 0x400E00 0x401000}
puts "initial: synced=[synced] busy=[busy]"
foreach {name proc} {naive inj_naive handshake inj_hs handshake+sync inj_hs_sync} {
  set land 0
  foreach fr $FR {
    set d0 [dbg 6]
    $proc $fr 20 0x8
    after 900
    if {[expr {[dbg 6]-$d0}] > 0} { incr land }
    # undo with the same protocol
    $proc $fr 20 0x8
    after 700
  }
  puts [format "protocol %-16s : %d/%d injections produced a filtered detection" $name $land [llength $FR]]
}
puts "final: synced=[synced] busy=[busy] init=[expr {([st]>>16)&1}]"
