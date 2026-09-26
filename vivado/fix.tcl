connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
proc s4 {} { return [mrd -force -value 0x43C00010] }
proc s5 {} { return [mrd -force -value 0x43C00014] }
set states {idle read_mem parity_calc stop_read_mem}
proc show {t} { upvar states states; set a [s4]; set b [s5]; set pc [expr {($b>>24)&0xFF}]
  puts [format "%s state=%s init=%d grant=%d synced=%d busy=%d req=%d | scan_cnt=%d diag=0x%02X" \
   $t [lindex $states [expr {$pc&7}]] [expr {($pc>>3)&1}] [expr {($pc>>4)&1}] [expr {($pc>>5)&1}] [expr {($pc>>6)&1}] [expr {($pc>>7)&1}] [expr {($a>>8)&0xFF}] [expr {($a>>16)&0xFF}]] }
show "before fix:"
# HAND OFF ICAP FIRST, then reset the PL so scrubber retries sync with ICAP available
mwr -force 0xF8007000 0x4600E07F
mwr -force 0xF8000008 0x0000DF0D
mwr -force 0xF8000240 0x0000000F; after 50; mwr -force 0xF8000240 0x00000000
after 300
show "after reset+1:"
after 500
show "after reset+2:"
after 1000
show "after +1.5s:"
