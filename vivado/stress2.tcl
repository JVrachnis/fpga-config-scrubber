connect
targets -set -filter {name =~ "ARM*#0"}
proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }
set stuck {}
proc tryf {fr w m} {
  global stuck
  mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
  set t0 [clock milliseconds]; set n 0
  while {[clock milliseconds]-$t0 < 900} {
    cc; after 25
    if {[expr {[mrd -force -value 0x43C00014]&2}]} {
      if {[expr {[mrd -force -value 0x43C00018]&0xFFFFFF}] == $fr+2} { incr n } } }
  if {$n > 5} { lappend stuck [format "0x%06X/w%d" $fr $w]
    mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
    mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1; after 400 }
}
foreach f {0x0980 0x0A00 0x0A80 0x0B80 0x0C00 0x0D00 0x0E00 0x1000 0x1200 0x1400 0x1600 0x400A00 0x400C00 0x401000} {
  tryf $f 10 0x8
  tryf $f 55 0x1000
}
puts "STRESS2: [llength $stuck] stuck: $stuck"
