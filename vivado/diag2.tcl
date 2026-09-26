connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
proc st {} { return [mrd -force -value 0x43C00010] }
proc diag {} { return [expr {([st] >> 16) & 0xFF}] }
# read diag right after config (before ICAP handoff)
puts [format "diag before handoff: 0x%02X   STATUS=0x%08X" [diag] [st]]
# ICAP handoff, then re-read over ~1s
mwr -force 0xF8007000 0x4600E07F
after 100
puts [format "diag after handoff : 0x%02X   scan_cnt=%d" [diag] [expr {([st]>>8)&0xFF}]]
after 500
set d [diag]
puts [format "diag after +500ms  : 0x%02X   scan_cnt=%d" $d [expr {([st]>>8)&0xFF}]]
puts "--- decode (1=yes) ---"
puts "  bit0 parity_initialized      : [expr {$d & 1}]"
puts "  bit1 start_parity_calc ever  : [expr {($d>>1)&1}]"
puts "  bit2 parity_calc_done ever   : [expr {($d>>2)&1}]"
puts "  bit3 start_err_correction ev : [expr {($d>>3)&1}]"
puts "  bit4 par-calc ICAP request   : [expr {($d>>4)&1}]"
puts "  bit5 par-calc ICAP granted ev: [expr {($d>>5)&1}]"
puts "  bit6 edc ICAP request ever   : [expr {($d>>6)&1}]"
puts "  bit7 edc ICAP granted ever   : [expr {($d>>7)&1}]"
