connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F
proc cc {} { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }
proc doinj {fr w m} { mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1 }
proc decode {syn} {
  set odd [expr {($syn >> 12) & 1}]; set wf [expr {($syn >> 5) & 0x7F}]; set b [expr {$syn & 0x1F}]
  if {$wf >= 64} { set w [expr {$wf - 27}] } elseif {$wf >= 32} { set w [expr {$wf - 26}] } elseif {$wf >= 25} { set w [expr {$wf - 25}] } else { set w -1 }
  return [list $odd $w $b]
}
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
after 800

puts "=== E3: paced single-bit sweep at pristine frame 0x0A00 (syndrome must track) ==="
foreach {w m eb} {5 0x8 3  10 0x100 8  24 0x80000 19  50 0x80000000 31} {
  cc; after 300
  doinj 0x0A00 $w $m
  after 1500
  set fl [expr {[mrd -force -value 0x43C00014] & 7}]
  set far [mrd -force -value 0x43C00018]
  set syn [expr {[mrd -force -value 0x43C0001C] & 0x1FFF}]
  lassign [decode $syn] odd dw db
  cc; after 1500
  set fl2 [expr {[mrd -force -value 0x43C00014] & 7}]
  puts [format "  cmd(w=%2d bit=%2d) -> cap far=0x%08X syn=0x%04X dec(odd=%d w=%d bit=%d) flags=0x%X | corrected=%s" \
        $w $eb $far $syn $odd $dw $db $fl [expr {$fl2==0?"Y":"N(0x[format %X $fl2])"}]]
}

puts "=== E4: THE 2-D SHOT - adjacent double-bit on silicon ==="
foreach {fr w m desc} {0x0C00 10 0x30 "bits4-5" 0x0E00 33 0x18000 "bits15-16"} {
  cc; after 300
  doinj $fr $w $m
  after 1500
  set fl [expr {[mrd -force -value 0x43C00014] & 7}]
  set far [mrd -force -value 0x43C00018]
  set syn [expr {[mrd -force -value 0x43C0001C] & 0x1FFF}]
  lassign [decode $syn] odd dw db
  cc; after 2500
  set fl2 [expr {[mrd -force -value 0x43C00014] & 7}]
  set far2 [mrd -force -value 0x43C00018]
  puts [format "  DOUBLE %s @far=0x%06X w=%d: cap far=0x%08X syn=0x%04X (odd=%d) flags=0x%X | after 2.5s: flags=0x%X far=0x%08X %s" \
        $desc $fr $w $far $syn $odd $fl $fl2 $far2 [expr {$fl2==0?"<== CORRECTED: 2-D ON SILICON":"(recurs/uncorrected)"}]]
}
puts "DONE"
