# Does CTRL bit11 stop the scrubber core's clock, and does it resume cleanly?
#
# The AXI interface is on the ungated clock, so its counters keep running and
# remain readable while the core is frozen. The core's own progress indicator
# (frames read) must stop dead and then continue.
connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1500
proc dbg {sel base} {
  mwr -force 0x43C0000C [expr {$base | ($sel<<8)}]; after 5
  set v [mrd -force -value 0x43C0001C]
  mwr -force 0x43C0000C $base; return $v
}
proc scanctr {} { return [expr {([mrd -force -value 0x43C00010]>>8)&0xFF}] }

puts "=== running normally ==="
set a [dbg 2 0x1]; after 300; set b [dbg 2 0x1]
puts [format "frames: %d -> %d   (delta %d, core is running)" $a $b [expr {$b-$a}]]
puts [format "scan counter: %d -> %d" [scanctr] [scanctr]]

puts "=== FREEZE_CLK asserted (CTRL bit 11) ==="
mwr -force 0x43C0000C 0x801; after 100
set c [dbg 2 0x801]
set s1 [scanctr]
after 500
set d [dbg 2 0x801]
set s2 [scanctr]
puts [format "frames: %d -> %d   (delta %d, MUST be 0)" $c $d [expr {$d-$c}]]
puts [format "scan counter: %d -> %d  (MUST be equal)" $s1 $s2]
puts [format "AXI still alive while frozen: us_timer moves %d" [expr {[dbg 1 0x801]-[dbg 1 0x801]}]]
set t1 [dbg 1 0x801]; after 200; set t2 [dbg 1 0x801]
puts [format "us_timer: %d -> %d (delta %d, AXI clock is NOT gated)" $t1 $t2 [expr {$t2-$t1}]]

puts "=== released ==="
mwr -force 0x43C0000C 0x1; after 200
set e [dbg 2 0x1]; after 300; set f [dbg 2 0x1]
puts [format "frames: %d -> %d   (delta %d, core resumed)" $e $f [expr {$f-$e}]]
puts [format "init=%d  (state survived the freeze)" [expr {([mrd -force -value 0x43C00010]>>16)&1}]]
