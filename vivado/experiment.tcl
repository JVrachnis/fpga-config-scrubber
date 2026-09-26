connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
# reprogram PL with the new observability bitstream
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc st {} { return [mrd -force -value 0x43C00010] }
proc cnt {} { return [expr {([st] >> 8) & 0xFF}] }
# 1) LIVENESS: is the scrubber scanning? read scan_counter twice
set c1 [cnt]; after 300; set c2 [cnt]
puts "SCAN_COUNTER: $c1 -> $c2   (changed => scrubber is reading frames)"
puts "STATUS pre: [format 0x%08X [st]]  (bit3 fifo_empty=1 means no ECC event)"
# 2) clear any stale capture
mwr -force 0x43C0000C 0x10; after 5; mwr -force 0x43C0000C 0x0
# 3) INJECT single bit: in-range frame, word 10, mask 0x1
mwr -force 0x43C00000 0x00000920
mwr -force 0x43C00004 0x0000000A
mwr -force 0x43C00008 0x00000001
mwr -force 0x43C0000C 0x1 ; after 2
mwr -force 0x43C0000C 0x7 ; after 20   ;# start injection
mwr -force 0x43C0000C 0x1              ;# stop re-injecting, let scrubber correct
# 4) DETECTION: poll for captured ECC event (fifo_empty -> 0)
set det 0
for {set i 0} {$i < 400} {incr i} {
  set s [st]
  if {(($s >> 3) & 1) == 0} { set det 1; break }
  after 5
}
puts "DETECTION: [expr {$det ? {YES} : {no}}] after $i polls"
puts "  cap_flags(0x14): [format 0x%08X [mrd -force -value 0x43C00014]]  (bit2 eccsingle,bit1 ecc,bit0 crc)"
puts "  cap_FAR(0x18):   [format 0x%08X [mrd -force -value 0x43C00018]]  (injected frame was 0x920)"
puts "  cap_SYN(0x1C):   [format 0x%08X [mrd -force -value 0x43C0001C]]  (nonzero => error syndrome)"
# 5) CORRECTION: ack the latch, wait, confirm it stays clean (frame fixed by scrubber)
mwr -force 0x43C0000C 0x10; after 5; mwr -force 0x43C0000C 0x1
after 300
set s2 [st]
set recap [expr {(($s2 >> 3) & 1) == 0}]
puts "AFTER ACK+WAIT: STATUS=[format 0x%08X $s2]  recaptured=[expr {$recap ? {YES-still erroring} : {no-clean}}]"
set c3 [cnt]
puts "SCAN_COUNTER now: $c3  (still advancing => scrubber alive after experiment)"
puts "VERDICT: [expr {($det && !$recap) ? {DETECTED then CORRECTED} : ($det ? {detected, still erroring} : {no detection})}]"
