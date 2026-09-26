# The injector guard (Rev. 1.15): invalid and dynamic FARs must be REFUSED
# (STATUS bit6 / bit7) and must corrupt nothing.
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
after 2000
proc rej {} { return [expr {([stat]>>6)&3}] }
puts "case                       far       rejected(6=invalid,7=dynamic)  neighbour corrupted?"
# invalid minors that corrupted before: col22 m33 (28 minors), col34 m33 (30 minors)
foreach v {{invalid-minor 0x000B21 0x000B00} {invalid-minor 0x001121 0x001100} {dynamic-col-bot 0x400A23 0x400A22} {dynamic-col-top 0x000A23 0x000A22} {valid 0x001304 0x001305}} {
  lassign $v name F NB
  set base [readframe $NB]; set baseF {}
  if {$name eq "valid"} { set baseF [readframe $F] }
  drain; inject 0x1 $F 20 0x8; after 50
  set r [rej]
  set d [llength [framediff $base [readframe $NB]]]
  set self ""
  if {$name eq "valid"} { set self "  self diff after: [framediff $baseF [readframe $F]]"; inject 0x1 $F 20 0x8 }
  puts [format "%-26s %-9s %-30s %d%s" $name $F [expr {$r==1?"bit6 invalid":($r==2?"bit7 dynamic":($r==3?"both":"accepted"))}] $d $self]
}
puts "[recword]"
