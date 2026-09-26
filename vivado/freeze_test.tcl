# Does withdrawing the scrubber's ICAP requests let the injector actually plant?
#
# Hypothesis: the 2026 continuous-scan loop holds the configuration port almost
# permanently, the injector never wins a grant, and its Start is dropped. That
# would explain a ~25% landing rate from JTAG *and* from the 2021 PS
# application, and why that application worked in 2019-21 when the scrubber was
# reactive and the port was usually free.
#
# CTRL bit7 (TEST_FREEZE) withdraws every scrubber request; STATUS bit4
# (ICAP_FREE) reports when the port is actually free.
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
proc st {} { return [mrd -force -value 0x43C00010] }
proc icap_free {} { return [expr {([st] >> 4) & 1}] }

# --- how often is the port free while the scrubber runs normally?
set free 0
for {set i 0} {$i < 20} {incr i} { incr free [icap_free]; after 20 }
puts "ICAP free while scanning normally : $free / 20 samples"

mwr -force 0x43C0000C 0x81; after 50          ;# TEST_FREEZE
set free 0
for {set i 0} {$i < 20} {incr i} { incr free [icap_free]; after 20 }
puts "ICAP free with TEST_FREEZE asserted: $free / 20 samples"
mwr -force 0x43C0000C 0x1; after 50

# --- landing rate, frozen vs not
proc inj_frozen {fr w m} {
  mwr -force 0x43C0000C 0x81; after 30             ;# freeze, release the port
  set g 0
  while {![icap_free] && $g < 100} { incr g; after 5 }
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x81; after 4
  mwr -force 0x43C0000C 0x87; after 60             ;# start, still frozen
  mwr -force 0x43C0000C 0x81; after 20
  mwr -force 0x43C0000C 0x1                        ;# release -> scrubber resumes
}
proc inj_plain {fr w m} {
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
}
set FR {0x000A00 0x000C00 0x000E00 0x001000 0x001200 0x001400 0x400A00 0x400C00 0x400E00 0x401000}
foreach {name p} {plain inj_plain frozen inj_frozen} {
  set land 0
  foreach fr $FR {
    set d0 [dbg 6]
    $p $fr 20 0x8
    after 900
    if {[expr {[dbg 6]-$d0}] > 0} { incr land }
    $p $fr 20 0x8                                   ;# undo, same protocol
    after 700
  }
  puts [format "protocol %-8s : %2d/%d produced a filtered detection" $name $land [llength $FR]]
}
puts "final: init=[expr {([st]>>16)&1}] icap_free=[icap_free]"
