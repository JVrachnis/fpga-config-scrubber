connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
# baseline: scrubber free-running, ECC should be clean
puts "BASELINE FLAGS(0x14): [format 0x%08X [mrd -force -value 0x43C00014]]"
# --- inject ONE bit: frame in-range, word 10, single-bit mask ---
mwr -force 0x43C00000 0x00000920 ;# frame addr (inside 0x000900..0x401ba9)
mwr -force 0x43C00004 0x0000000A ;# word position 10
mwr -force 0x43C00008 0x00000001 ;# single-bit fault mask
mwr -force 0x43C0000C 0x1        ;# icap_ready
after 5
mwr -force 0x43C0000C 0x7        ;# ready+request+Start -> perform injection
# rapid capture of FRAME_ECC events (FIFO-latched) for ~1s
set seen 0
for {set i 0} {$i < 300} {incr i} {
  set fl [mrd -force -value 0x43C00014]
  if {$fl != 0} {
    set far [mrd -force -value 0x43C00018]
    set syn [mrd -force -value 0x43C0001C]
    puts "ECC EVENT @poll $i  FLAGS=[format 0x%08X $fl] FAR=[format 0x%08X $far] SYN=[format 0x%08X $syn]"
    incr seen
    if {$seen >= 6} break
  }
}
# stop re-injecting, leave scrubber running
mwr -force 0x43C0000C 0x1
after 200
puts "AFTER FLAGS(0x14): [format 0x%08X [mrd -force -value 0x43C00014]]"
puts "STATUS(0x10): [format 0x%08X [mrd -force -value 0x43C00010]]"
puts "TOTAL_ECC_EVENTS: $seen"
