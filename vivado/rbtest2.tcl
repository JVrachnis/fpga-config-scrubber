connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
after 2000
foreach G {0xC00158 0xC00100 0xC0023D 0x400B00 0x001304} {
  freeze; set g [readframe $G 0x881]; thaw; after 100
  set nz 0; foreach w $g { if {$w != 0} { incr nz } }
  puts [format "%-9s nonzero words %3d/101   w0..3: %08X %08X %08X %08X  w50: %08X" $G $nz [lindex $g 0] [lindex $g 1] [lindex $g 2] [lindex $g 3] [lindex $g 50]]
}
# does a block-1 write take at all? try unfrozen (plain) too
set G 0xC00158
set g0 [readframe $G]
inject 0x1 $G 36 0x01000000
set g1 [readframe $G]
puts "plain flip on $G: diff [framediff $g0 $g1]"
inject 0x1 $G 36 0x01000000
