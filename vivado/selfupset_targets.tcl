# Self-upset target list: the configuration bits that ARE the scrubber.
#
# write_bitstream -logic_location_file emits, for every used flip-flop, LUT
# and block-RAM bit, the frame address and bit offset that hold it. Filter to
# the scrubber hierarchy and group by frame -> the frames whose corruption
# would upset the scrubber's own logic. Injecting there is the only silicon
# test of the hardening layers (safe-state FSMs, golden byte parity, TMR,
# watchdog): a flip in a scrubber frame must be corrected BY the scrubber
# without the scrubber losing its state or its golden reference.
#
# Run on the routed checkpoint of the current build:
#   vivado -mode batch -source selfupset_targets.tcl
set run $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.runs/impl_1
open_checkpoint $run/scrubber_injection_wrapper_routed.dcp
write_bitstream -force -logic_location_file /tmp/selfupset/design.bit
# design.ll lines:  Bit <offset> 0x<frame> <bit> Block=<site> Latch=<..> Net=<hier/net>
set fh [open /tmp/selfupset/design.ll r]
set n_all 0; set n_scrub 0
array set frames {}
while {[gets $fh line] >= 0} {
  if {![string match "Bit *" $line]} { continue }
  incr n_all
  if {![regexp {Bit\s+\d+\s+0x([0-9A-Fa-f]+)\s+(\d+)\s+Block=(\S+).*Net=(\S+)} $line -> far bit site net]} { continue }
  if {![string match "*scrubber_wrapper_0/inst/scrubber/*" $net]} { continue }
  incr n_scrub
  # frame bit -> word/bit within the 101x32 frame
  set word [expr {$bit / 32}]; set b [expr {$bit % 32}]
  # module = first hierarchy element below the scrubber
  regexp {inst/scrubber/([^/]+)} $net -> mod
  lappend frames(0x$far) [list $word $b $mod $net]
}
close $fh
set out [open $::env(SCRUBBER_ROOT)/vivado/selfupset_targets.tcl.out w]
puts $out "# far word bit module net   ($n_scrub scrubber bits of $n_all, [array size frames] frames)"
foreach f [lsort [array names frames]] {
  foreach e $frames($f) { puts $out "$f [lindex $e 0] [lindex $e 1] [lindex $e 2] [lindex $e 3]" }
}
close $out
puts "SELFUPSET: $n_scrub scrubber bits in [array size frames] frames (of $n_all design bits)"
# per-module summary
array set bymod {}
foreach f [array names frames] { foreach e $frames($f) { incr bymod([lindex $e 2]) } }
foreach m [lsort [array names bymod]] { puts [format "  %-28s %6d bits" $m $bymod($m)] }
