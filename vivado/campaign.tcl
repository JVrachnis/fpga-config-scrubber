connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc capf {} { return [expr {[mrd -force -value 0x43C00014]&7}] }
proc far {} { return [mrd -force -value 0x43C00018] }
proc clearcap {} { mwr -force 0x43C0000C 0x10; after 3; mwr -force 0x43C0000C 0x0 }
proc injonly {fr word mask} { mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $word; mwr -force 0x43C00008 $mask
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 40; mwr -force 0x43C0000C 0x1 }
# prime scrubber (handoff + one sync)
injonly 0x2000 0x0A 0x0; after 500; clearcap; after 200
puts "== autonomous fault campaign: inject single-bit, let scan detect, verify correct =="
set pass 0; set total 0
foreach {fr wd} {0x2000 0x0A 0x2000 0x05 0x4000 0x0A 0x6000 0x14 0x8000 0x0A 0xA000 0x1E 0x00010000 0x0A} {
  clearcap; after 100
  injonly $fr $wd 0x1            ;# inject one bit, NO manual re-read
  after 400                      ;# let the autonomous scan find it
  set d [capf]; set f [far]
  # verify correction: clear, wait several scan sweeps, check no re-detect
  clearcap; after 1200
  set d2 [capf]
  incr total
  set detok [expr {$d != 0}]; set corrok [expr {$d2 == 0}]
  if {$detok && $corrok} { incr pass; set res "PASS detect+correct" } elseif {$detok} { set res "detect-only (persist?)" } else { set res "no-detect" }
  puts [format "  frame=0x%08X word=%2d : detect=0x%X FAR=0x%08X  recheck=0x%X  -> %s" $fr $wd $d $f $d2 $res]
}
puts "== $pass/$total autonomous detect+correct =="
