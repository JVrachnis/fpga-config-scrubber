connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
ps7_init; ps7_post_config
# hand config interface from PCAP to PL ICAPE2 (devcfg CTRL)
mwr -force 0xF8007000 0x4600E07F
# safe params: mask 0 = writeback with no modification
mwr -force 0x43C00000 0x0   ;# frame
mwr -force 0x43C00004 0x0   ;# word pos
mwr -force 0x43C00008 0x0   ;# fault mask (0 = no bit flipped)
# icap_on: icap_ready
mwr -force 0x43C0000C 0x1
after 10
# FI_start: icap_ready + icap_request + Start
mwr -force 0x43C0000C 0x7
# poll STATUS bit0 (synced) up to ~2s
set synced 0
for {set i 0} {$i < 200} {incr i} {
  set s [mrd -force -value 0x43C00010]
  if {$s & 1} { set synced 1; break }
  after 10
}
puts "SYNCED_BIT: [expr {$synced}]  after ${i} polls"
puts "STATUS(0x10): [format 0x%08X [mrd -force -value 0x43C00010]]  (bit0=synced bit1=busy bit2=fifo_full bit3=fifo_empty)"
puts "FECC_FLAGS(0x14): [format 0x%08X [mrd -force -value 0x43C00014]]  (bit0=crc bit1=ecc bit2=eccsingle)"
puts "FECC_FAR(0x18): [format 0x%08X [mrd -force -value 0x43C00018]]"
puts "FECC_SYN(0x1C): [format 0x%08X [mrd -force -value 0x43C0001C]]"
