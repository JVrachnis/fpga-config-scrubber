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
  puts [format "%-22s raw@edge=%-6d raw@d=%-6d filt@edge=%-6d filt@d=%-6d corr_done=%-6d  frames=%d" \
        $tag [dbg 3] [dbg 4] [dbg 5] [dbg 6] [dbg 7] [dbg 2]]
}
snap "idle (fresh)"
after 1000
snap "idle +1s"
# inject a single-bit error into a valid frame
mwr -force 0x43C00000 0x001800; mwr -force 0x43C00004 10; mwr -force 0x43C00008 0x8
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 400
snap "after 1 injection"
after 1000
snap "  +1s"
# ten more injections
for {set i 0} {$i < 10} {incr i} {
  mwr -force 0x43C00000 [expr {0x001880 + $i}]; mwr -force 0x43C00004 [expr {10+$i}]; mwr -force 0x43C00008 0x8
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
  after 150
}
after 500
snap "after 10 more"
