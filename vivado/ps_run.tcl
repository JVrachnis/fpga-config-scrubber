# Run the 2021 PS application (injector_ap.elf) on the ARM core and see whether
# ITS injections land, measured with the filtered-detection counter.
#
# This is a controlled comparison: the ELF is the injector implementation that
# was actually used to produce the original project's results, running on the
# PS with microsecond-scale access, against our 2026 xsdb scripts which reach
# the same registers through a 2.49 ms JTAG round trip.
#
# The app injects num_of_injections=4 upsets into column 18
# (frames 0x908,0x906,0x904,0x902 / words 1,2,3,0 / masks 0x1,0x2,0x200,0x4)
# and then desyncs. It is not stripped, so its globals can be read back.
connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1500

proc dbg {sel} {
  mwr -force 0x43C0000C [expr {0x1 | ($sel<<8)}]; after 5
  set v [mrd -force -value 0x43C0001C]
  mwr -force 0x43C0000C 0x1; return $v
}
proc snap {tag} {
  puts [format "%-24s filt_det=%-6d corrections=%-6d frames=%d" $tag [dbg 6] [dbg 7] [dbg 2]]
}
snap "before PS app"

stop
dow $::env(SCRUBBER_ROOT)/rtl/modules/injection_PS/Debug/injector_ap.elf
puts "ELF loaded; running..."
con
after 4000
stop
puts "PS app halted"
snap "after PS app"
after 2000
snap "  +2 s"

# read what the app itself recorded
foreach v {num_of_injections ECC_far ECC_SYNDROME ECC_status ECC_error} {
  if {[catch {set val [print $v]} err]} { puts "  $v : <unreadable>" } else { puts "  $val" }
}
puts "status: [format 0x%08X [mrd -force -value 0x43C00010]]"
