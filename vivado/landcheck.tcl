# Deterministic non-detections (det=0, exact=1, hw_det saturated): does the bit land?
# 0x40111B w33 b27: failed in 02/03/03b/08 (4/4); 0x001308 w50 b18: 02/03/03b (3/3).
# Plus the CERN_405 frames (replay S2 failure: seen_held 1/4, dirty, wd_delta 3).
connect
source $::env(SCRUBBER_ROOT)/vivado/lib.tcl
board_up
after 2000
foreach v {{0x40111B 33 0x08000000} {0x40111B 33 0x08000000} {0x001308 50 0x00040000} {0x001308 50 0x00040000} {0x40111B 47 0x00002000} {0x40111A 47 0x00001000} {0x40110E 48 0x00000008} {0x40110F 48 0x00000004} {0x40111B 33 0x00000008} {0x001308 20 0x00040000}} {
  lassign $v F W M
  set base [readframe $F]
  drain; inject 0x1 $F $W $M
  set landed [framediff $base [readframe $F]]
  set h [first_hit [expr {$F+2}] 2500]
  after 300; set now [framediff $base [readframe $F]]
  puts [format "%-9s w%-3d %s  landed=%-16s first_ms=%5d  rehits=%d after=%s  %s  %s" $F $W $M [expr {[llength $landed]?$landed:"NO"}] $h [hits_in [expr {$F+2}] 800] [expr {[llength $now]?$now:"clean"}] [recword] [livestr [live]]]
  if {[llength $now]} { inject 0x1 $F $W $M; after 200 }
  drain
}
puts "=== LANDCHECK done ==="
