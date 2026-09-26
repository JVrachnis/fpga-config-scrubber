connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc s4 {} { return [mrd -force -value 0x43C00010] }
proc rd {a} { return [mrd -force -value $a] }
proc rpt {t} { set a [s4]
  puts [format "%s scan_cnt=%d scrub_diag=0x%02X | cap_flags(0x14[2:0])=0x%X FAR(0x18)=0x%08X SYN(0x1C)=0x%08X" \
    $t [expr {($a>>8)&0xFF}] [expr {($a>>16)&0xFF}] [expr {[rd 0x43C00014]&7}] [rd 0x43C00018] [rd 0x43C0001C]] }
# prime scrubber init
mwr -force 0x43C00008 0x0; mwr -force 0x43C0000C 0x1; after 5; mwr -force 0x43C0000C 0x7; after 40; mwr -force 0x43C0000C 0x1
after 200
# clear any stale ECC capture (reg3 bit4 ack)
mwr -force 0x43C0000C 0x10; after 5; mwr -force 0x43C0000C 0x0
rpt "primed+cleared:"
# STEP A: inject a real single-bit fault at frame 0x920 word10
mwr -force 0x43C00000 0x00000920; mwr -force 0x43C00004 0x0A; mwr -force 0x43C00008 0x1
mwr -force 0x43C0000C 0x1; after 5; mwr -force 0x43C0000C 0x7; after 40; mwr -force 0x43C0000C 0x1
rpt "after-inject:  "
# STEP B: re-READ that frame (mask=0) so FRAME_ECC sees the error while scrubber is armed
mwr -force 0x43C00008 0x0
mwr -force 0x43C0000C 0x1; after 5; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 200
rpt "after-reread:  "
after 1000
rpt "+1s:           "
