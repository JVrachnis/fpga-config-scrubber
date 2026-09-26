# Re-test the vectors that failed the large-N campaign, three ways each:
#   live   - inject with the scrubber scanning (as in the campaign)
#   paused - pause the scan, inject, resume  (removes any injector/scrubber race)
#   live2  - live again, to see whether failure is reproducible at all
# If "paused" passes where "live" fails, the failure is a race between the
# JTAG-paced read-modify-write injector and the live scrubber, not a limit of
# the correction code.
connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1500

proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }
proc inj {fr w m} {
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
}
proc hits {target ms} {
  set t [clock milliseconds]; set h 0
  while {[clock milliseconds]-$t < $ms} {
    cc; after 25
    if {[expr {[mrd -force -value 0x43C00014] & 2}]} {
      if {[expr {[mrd -force -value 0x43C00018] & 0xFFFFFF}] == $target} { incr h } } }
  return $h
}
proc trial {fr w m mode} {
  set target [expr {$fr+2}]
  cc; after 40
  if {$mode eq "paused"} { mwr -force 0x43C0000C 0x21; after 30 }
  inj $fr $w $m
  if {$mode eq "paused"} { after 30; mwr -force 0x43C0000C 0x1 }
  after 400
  set h [hits $target 600]
  set ok [expr {$h == 0}]
  if {!$ok} {                     ;# clean up
    if {$mode eq "paused"} { mwr -force 0x43C0000C 0x21; after 30 }
    inj $fr $w $m
    if {$mode eq "paused"} { after 30; mwr -force 0x43C0000C 0x1 }
    after 500
  }
  return $ok
}

set V {
  {0x4019A0 66 0x01000000 single}
  {0x00130C 96 0x00000008 single}
  {0x001412 38 0x00040000 single}
  {0x000A9C 10 0x00020000 single}
  {0x001411 84 0x07800000 adj4}
  {0x000D0F 39 0x00001E00 adj4}
  {0x000B16 56 0x00000300 adj2}
  {0x401192 97 0x00060000 adj2}
}
puts "vector                          kind    live paused live2"
foreach v $V {
  lassign $v fr w m kind
  set a [trial $fr $w $m live]
  set b [trial $fr $w $m paused]
  set c [trial $fr $w $m live]
  puts [format "0x%06X w%-3d 0x%08X  %-6s  %-4s %-6s %-5s" $fr $w $m $kind \
        [expr {$a ? "ok" : "FAIL"}] [expr {$b ? "ok" : "FAIL"}] [expr {$c ? "ok" : "FAIL"}]]
}
puts "final init=[expr {([mrd -force -value 0x43C00010]>>16)&1}]"
