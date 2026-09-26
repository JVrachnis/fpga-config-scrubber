connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
proc s4 {} { return [mrd -force -value 0x43C00010] }
proc s5 {} { return [mrd -force -value 0x43C00014] }
set states {idle read_mem parity_calc stop_read_mem}
proc show {t} {
  upvar states states
  set a [s4]; set b [s5]
  set rf [expr {($b>>19)&0x1F}]; set pc [expr {($b>>24)&0xFF}]
  puts [format "%s STATUS=0x%08X reg5=0x%08X" $t $a $b]
  puts [format "   sentinel(exp1)=%d aresetn=%d reset=%d enable=%d gpm_init=%d" [expr {($rf>>4)&1}] [expr {$rf&1}] [expr {($rf>>1)&1}] [expr {($rf>>2)&1}] [expr {($rf>>3)&1}]]
  puts [format "   pcalc: state=%s init=%d grant=%d synced=%d busy=%d req=%d" [lindex $states [expr {$pc&7}]] [expr {($pc>>3)&1}] [expr {($pc>>4)&1}] [expr {($pc>>5)&1}] [expr {($pc>>6)&1}] [expr {($pc>>7)&1}]]
  puts [format "   scan_cnt=%d scrub_diag=0x%02X" [expr {($a>>8)&0xFF}] [expr {($a>>16)&0xFF}]]
}
show "at-config:"
mwr -force 0xF8007000 0x4600E07F
after 300
show "post-handoff:"
after 1000
show "post +1s:"
