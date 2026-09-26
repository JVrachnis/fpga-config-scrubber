# Does scan-pause actually isolate an injected error from the corrector?
#
# If the injector's own ICAP read makes FRAME_ECCE2 emit a syndrome, the handler
# will start an episode and the parity calculator will request the ICAP directly
# - a path the scan-pause bit does not gate. The error would then be corrected
# within microseconds of being planted, i.e. long before a second JTAG injection
# (~65 ms) can land, making concurrent multi-frame upsets impossible to create
# with this injector.
#
# Test: pause, inject, and poll for the error WHILE STILL PAUSED.
#   error visible and persisting  -> pause isolates; concurrency is achievable
#   error already gone            -> the injection self-reveals and self-heals
connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1500
proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }

set F 0x001800
puts "=== paused injection, observed WHILE STILL PAUSED ==="
mwr -force 0x43C0000C 0x21; after 30          ;# pause scan
set sc1 [expr {([mrd -force -value 0x43C00010]>>8)&0xFF}]
cc; after 30
mwr -force 0x43C00000 $F; mwr -force 0x43C00004 10; mwr -force 0x43C00008 0x300
mwr -force 0x43C0000C 0x21; after 4; mwr -force 0x43C0000C 0x27; after 60; mwr -force 0x43C0000C 0x21
# --- still paused: is the freshly planted error visible?
set seen 0
for {set i 0} {$i < 20} {incr i} {
  cc; after 25
  if {[expr {[mrd -force -value 0x43C00014] & 2}]} {
    if {[expr {[mrd -force -value 0x43C00018] & 0xFFFFFF}] == [expr {$F+2}]} { incr seen } }
}
set sc2 [expr {([mrd -force -value 0x43C00010]>>8)&0xFF}]
puts "paused: scan counter $sc1 -> $sc2 (equal => scan really is stopped)"
puts "paused: captures at target during 500 ms = $seen"
mwr -force 0x43C0000C 0x1; after 400          ;# resume
set post 0
for {set i 0} {$i < 20} {incr i} {
  cc; after 25
  if {[expr {[mrd -force -value 0x43C00014] & 2}]} {
    if {[expr {[mrd -force -value 0x43C00018] & 0xFFFFFF}] == [expr {$F+2}]} { incr post } }
}
puts "after resume: captures at target during 500 ms = $post"
puts ""
puts "interpretation:"
puts "  seen>0 while paused  -> the injector's own ICAP read reveals the error"
puts "                          to FRAME_ECC; the corrector is NOT gated by pause"
puts "  seen=0 and post=0    -> the error was corrected before we could observe it"
puts "  seen=0 and post>0    -> pause isolates; error waited for the scan"
mwr -force 0x43C0000C 0x1
