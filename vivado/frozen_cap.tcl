# Frozen injection, verified with the capture path (independent of the debug mux).
# A landed upset in a valid frame must produce captures at FAR+2 until corrected.
connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 1500
proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }
proc icap_free {} { return [expr {([mrd -force -value 0x43C00010] >> 4) & 1}] }
proc watch {target ms tag} {
  set t [clock milliseconds]; set n 0; set other 0
  while {[clock milliseconds]-$t < $ms} {
    if {[expr {[mrd -force -value 0x43C00014] & 2}]} {
      if {[expr {[mrd -force -value 0x43C00018]&0xFFFFFF}] == $target} { incr n } else { incr other }
      cc
    }
    after 20
  }
  puts "   $tag: target captures=$n  other=$other"
  return $n
}
proc inj_frozen {fr w m} {
  mwr -force 0x43C0000C 0x81; after 30
  set g 0
  while {![icap_free] && $g < 100} { incr g; after 5 }
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x81; after 4
  mwr -force 0x43C0000C 0x87; after 80
  mwr -force 0x43C0000C 0x81; after 20
  mwr -force 0x43C0000C 0x1
}
proc inj_plain {fr w m} {
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 80; mwr -force 0x43C0000C 0x1
}
set F 0x001200
puts "baseline (no injection):"
watch [expr {$F+2}] 1500 "idle"
puts "PLAIN injection (scrubber holds the ICAP):"
inj_plain $F 20 0x8
watch [expr {$F+2}] 2500 "after plain"
inj_plain $F 20 0x8 ; after 800
puts "FROZEN injection (port released first):"
inj_frozen $F 20 0x8
watch [expr {$F+2}] 2500 "after frozen"
inj_frozen $F 20 0x8 ; after 800
puts "done. init=[expr {([mrd -force -value 0x43C00010]>>16)&1}]"
