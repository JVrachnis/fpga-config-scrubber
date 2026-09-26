connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc s4 {} { return [mrd -force -value 0x43C00010] }
proc capf {} { return [expr {[mrd -force -value 0x43C00014]&7}] }
proc scancnt {} { return [expr {([s4]>>8)&0xFF}] }
proc diag {} { return [expr {([s4]>>16)&0xFF}] }
proc clearcap {} { mwr -force 0x43C0000C 0x10; after 3; mwr -force 0x43C0000C 0x0 }
proc inj {fr word mask} { mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $word; mwr -force 0x43C00008 $mask
  mwr -force 0x43C0000C 0x1; after 3; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1 }
proc rpt {t} { puts [format "%s cap_flags=0x%X(bit2=single,bit1=ecc) FAR=0x%08X SYN=0x%08X | diag=0x%02X(bit3=correction) scan=%d" \
  $t [capf] [mrd -force -value 0x43C00018] [mrd -force -value 0x43C0001C] [diag] [scancnt]] }
inj 0x2000 0x0A 0x0; after 200; clearcap    ;# prime scrubber init
rpt "primed:       "
inj 0x2000 0x0A 0x1                          ;# inject ONE bit at valid frame 0x2000
clearcap
inj 0x2000 0x0A 0x0                          ;# re-read -> FRAME_ECC sees single-bit err -> scrubber should detect+correct
after 300
rpt "after inj+read:"
clearcap                                     ;# clear the detection latch
inj 0x2000 0x0A 0x0                          ;# re-read AGAIN: if corrected, now clean
after 200
rpt "recheck(corr?):"
