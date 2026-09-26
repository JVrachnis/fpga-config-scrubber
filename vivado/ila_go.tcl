connect
targets -set -filter {name =~ "ARM*#0"}
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 400
mwr -force 0x43C00000 0x0A23; mwr -force 0x43C00004 10; mwr -force 0x43C00008 0x8
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
puts "scrubber started + injected"
