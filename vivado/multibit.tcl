connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc capf {} { return [expr {[mrd -force -value 0x43C00014]&7}] }
proc far {} { return [mrd -force -value 0x43C00018] }
proc cc {} { mwr -force 0x43C0000C 0x10; after 3; mwr -force 0x43C0000C 0x0 }
proc inj {fr w m} { mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 50; mwr -force 0x43C0000C 0x1 }
inj 0x2000 0x0A 0x0; after 500; cc; after 300
puts "=== flags legend: bit0=crc bit1=ecc bit2=eccsingle ==="
# --- single bit (baseline, correctable by ECC) ---
cc; inj 0x2000 0x0A 0x1; after 400; set d [capf]; set f [far]; cc; after 1000; set d2 [capf]
puts [format "SINGLE-bit  0x2000: detect flags=0x%X FAR=0x%08X -> recheck=0x%X (%s)" $d $f $d2 [expr {$d2==0?{corrected}:{persist}}]]
# --- double bit in one frame (ECC alone cannot correct -> needs 2D) ---
foreach {fr m} {0x2000 0x3 0x4000 0x5 0x8000 0x30} {
  cc; inj $fr 0x0A $m; after 400; set d [capf]; set f [far]; cc; after 1200; set d2 [capf]
  puts [format "MULTI-bit   0x%X mask=0x%X: detect flags=0x%X FAR=0x%08X -> recheck=0x%X (%s)" $fr $m $d $f $d2 [expr {$d2==0?{corrected}:{persist}}]]
}
# --- single bits in two frames of same group ---
cc; inj 0x2000 0x0A 0x1; inj 0x2001 0x0A 0x1; after 500; set d [capf]; cc; after 1500; set d2 [capf]
puts [format "MULTI-frame 0x2000+0x2001: detect flags=0x%X -> recheck=0x%X (%s)" $d $d2 [expr {$d2==0?{corrected}:{persist}}]]
