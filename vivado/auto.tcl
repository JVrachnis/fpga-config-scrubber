connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc s4 {} { return [mrd -force -value 0x43C00010] }
proc scancnt {} { return [expr {([s4]>>8)&0xFF}] }
proc diag {} { return [expr {([s4]>>16)&0xFF}] }
proc capf {} { return [expr {[mrd -force -value 0x43C00014]&7}] }
# prime: run injector once so ICAP is synced and scrubber init completes
mwr -force 0x43C00008 0x0; mwr -force 0x43C0000C 0x1; after 5; mwr -force 0x43C0000C 0x7; after 40; mwr -force 0x43C0000C 0x1
after 300
puts "=== does scan_cnt now increment continuously? (scanner running) ==="
foreach t {0 0.3 0.6 1.0 2.0} { puts [format "  t=%ss scan_cnt=%d diag=0x%02X" $t [scancnt] [diag]]; after 400 }
puts "=== inject single-bit fault at valid frame 0x2000, then WATCH (no manual re-read) ==="
mwr -force 0x43C00000 0x00002000; mwr -force 0x43C00004 0x0A; mwr -force 0x43C00008 0x1
mwr -force 0x43C0000C 0x1; after 5; mwr -force 0x43C0000C 0x7; after 40; mwr -force 0x43C0000C 0x1
foreach t {0.2 0.5 1.0 2.0 4.0} { puts [format "  +%ss scan_cnt=%d cap_flags=0x%X diag=0x%02X(bit3=correction)" $t [scancnt] [capf] [diag]]; after 500 }
