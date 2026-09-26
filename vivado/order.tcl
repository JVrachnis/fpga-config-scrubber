connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
proc st {} { return [mrd -force -value 0x43C00010] }
proc diag {} { return [expr {([st]>>16)&0xFF}] }
proc cnt {} { return [expr {([st]>>8)&0xFF}] }
puts [format "at config:            diag=0x%02X cnt=%d" [diag] [cnt]]
# 1) hand PCAP->ICAP FIRST
mwr -force 0xF8007000 0x4600E07F
# 2) now reset the PL fabric so the scrubber restarts with ICAP available
mwr -force 0xF8000008 0x0000DF0D   ;# SLCR unlock
puts [format "FPGA_RST_CTRL before: 0x%08X  (SLCR unlocked)" [mrd -force -value 0xF8000240]]
mwr -force 0xF8000240 0x0000000F   ;# assert all 4 FCLK resets
after 50
puts [format "FPGA_RST_CTRL asserted: 0x%08X" [mrd -force -value 0xF8000240]]
mwr -force 0xF8000240 0x00000000   ;# release
after 200
puts [format "after PL reset (+200ms): diag=0x%02X cnt=%d" [diag] [cnt]]
after 800
set d [diag]
puts [format "after PL reset (+1s):    diag=0x%02X cnt=%d status=0x%08X" $d [cnt] [st]]
puts "  bit0 parity_initialized     : [expr {$d&1}]"
puts "  bit1 start_parity_calc ever : [expr {($d>>1)&1}]"
puts "  bit4 par-calc ICAP request  : [expr {($d>>4)&1}]"
puts "  bit5 par-calc ICAP grant ev : [expr {($d>>5)&1}]"
