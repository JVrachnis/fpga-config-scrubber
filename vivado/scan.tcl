connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc s4 {} { return [mrd -force -value 0x43C00010] }
set states {idle read_mem parity_calc stop_read_mem}
proc show {t} { upvar states states; set a [s4]; set p [expr {([mrd -force -value 0x43C00014]>>24)&0xFF}]
  puts [format "%s scrub_state=%s init=%d synced=%d busy=%d | scan_cnt=%d diag=0x%02X" \
    $t [lindex $states [expr {$p&7}]] [expr {($p>>3)&1}] [expr {($p>>5)&1}] [expr {($p>>6)&1}] [expr {($a>>8)&0xFF}] [expr {($a>>16)&0xFF}]] }
# prime ICAP by running the injector once (post-handoff)
mwr -force 0x43C00008 0x0; mwr -force 0x43C0000C 0x1; after 5; mwr -force 0x43C0000C 0x7; after 30; mwr -force 0x43C0000C 0x1
show "primed:  "
after 300;  show "+0.3s:   "
after 700;  show "+1.0s:   "
after 2000; show "+3.0s:   "
after 3000; show "+6.0s:   "
