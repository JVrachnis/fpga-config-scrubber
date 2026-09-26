connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc capflags {} { return [expr {[mrd -force -value 0x43C00014]&7}] }
proc scancnt {} { return [expr {([mrd -force -value 0x43C00010]>>8)&0xFF}] }
proc clearcap {} { mwr -force 0x43C0000C 0x10; after 3; mwr -force 0x43C0000C 0x0 }
proc inject {frame word mask} {
  mwr -force 0x43C00000 $frame; mwr -force 0x43C00004 $word; mwr -force 0x43C00008 $mask
  mwr -force 0x43C0000C 0x1; after 3; mwr -force 0x43C0000C 0x7; after 50; mwr -force 0x43C0000C 0x1
}
# prime
inject 0x920 0x0A 0x0; after 200; clearcap
puts "baseline cap=[capflags] scan=[scancnt]"
# sweep frames with full-word mask, re-read each, check for ANY error
foreach fr {0x920 0x0A00 0x1000 0x2000 0x00040000 0x00080000 0x100000} {
  inject $fr 0x0A 0xFFFFFFFF   ;# corrupt (all 32 bits of the word)
  set c1 [scancnt]
  inject $fr 0x0A 0x0          ;# re-read same frame (mask 0)
  set cf [capflags]; set c2 [scancnt]
  puts [format "frame 0x%08X : cap_flags=0x%X  scan %d->%d  FAR=0x%08X SYN=0x%08X" \
    $fr $cf $c1 $c2 [mrd -force -value 0x43C00018] [mrd -force -value 0x43C0001C]]
  clearcap
}
