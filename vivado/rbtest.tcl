connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
after 2000
set F 0x001304
puts "=== readback self-test ==="
set a [readframe $F]
set b [readframe $F]
puts "two reads of the same frame differ in: [framediff $a $b]   (expect none)"
puts "word 50 (ECC/clock word): [format 0x%08X [lindex $a 50]]   word 0: [format 0x%08X [lindex $a 0]]"
# plant a bit while HOLD is on (so the scrubber does not undo it), read back, remove it
ctrl 0x41
inject 0x41 $F 20 0x8
set c [readframe $F 0x41]
puts "after XOR w20 bit3 under HOLD, diff vs original: [framediff $a $c]   (expect w20:0x00000008)"
inject 0x41 $F 20 0x8
set d [readframe $F 0x41]
puts "after XOR back: [framediff $a $d]   (expect none)"
ctrl 0x1; after 300; drain
# and a golden BRAM content frame (block type 1): read, flip, read, restore
set G 0xC00158
freeze; set g0 [readframe $G 0x881]; thaw; after 200
freeze; inject 0x881 $G 36 0x01000000; set g1 [readframe $G 0x881]; thaw; after 300
puts "golden frame $G: flip w36 bit24 -> diff [framediff $g0 $g1]   [recword]"
freeze; inject 0x881 $G 36 0x01000000; set g2 [readframe $G 0x881]; thaw; after 300
puts "restored: diff [framediff $g0 $g2]   [recword]"
