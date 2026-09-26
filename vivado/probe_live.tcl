connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
select_arm
# do NOT reprogram: look at the board as the campaign left it
mwr -force 0x43C0000C 0x1
puts "STATUS: [format 0x%08X [stat]]  [recword]"
for {set i 0} {$i<5} {incr i} { puts "  live: [livestr [live]]  sc=[sc]"; after 200 }
puts "captures over 2 s: [collect 2000]"
inject 0x1 0x001304 20 0x8
puts "after inject: first_hit=[first_hit 0x001306 2500]  live: [livestr [live]]"
