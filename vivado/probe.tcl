# Does the injector actually RUN? Poll STATUS busy / ICAP_FREE across one
# injection, frozen and unfrozen, sampling as fast as JTAG allows.
connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1500

proc stat {} { return [mrd -force -value 0x43C00010] }
proc show {tag} {
  set s [stat]
  puts [format "  %-22s busy=%d free=%d idle=%d synced=%d capflag=%d" $tag \
        [expr {($s>>1)&1}] [expr {($s>>4)&1}] [expr {($s>>5)&1}] [expr {$s&1}] \
        [expr {[mrd -force -value 0x43C00014]&2 ? 1 : 0}]]
}
proc run_inject {base far word tag} {
  puts "--- $tag  (CTRL base 0x[format %x $base]) ---"
  mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C $base; after 20
  mwr -force 0x43C00000 $far; mwr -force 0x43C00004 $word; mwr -force 0x43C00008 0x8
  mwr -force 0x43C0000C $base; after 5
  show "before Start"
  mwr -force 0x43C0000C [expr {$base | 0x6}]
  for {set i 0} {$i<8} {incr i} { show "  during Start #$i" }
  mwr -force 0x43C0000C $base; after 30
  show "after Start cleared"
}

puts "=== A. plain (scrubber running, holds the ICAP) ==="
run_inject 0x1 0x001200 20 "plain"

puts ""
puts "=== B. scan paused (bit5) ==="
run_inject 0x21 0x001600 20 "scan_pause"

puts ""
puts "=== C. TEST_FREEZE only (bit7) ==="
run_inject 0x81 0x001A00 20 "test_freeze"

puts ""
puts "=== D. TEST_FREEZE + FREEZE_CLK (bit7|bit11) ==="
mwr -force 0x43C0000C 0x881; after 200
run_inject 0x881 0x001E00 20 "frozen"
mwr -force 0x43C0000C 0x1; after 300
show "released"
