# ============================================================================
# Silicon validation of r64b0554+ : mirrors the core_tb campaign on hardware
# (multi-bit injection excluded: on-chip injector is not ECC-aware)
# ============================================================================
connect
targets -set -filter {name =~ "ARM*#0"}
source $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl
fpga $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
ps7_init; ps7_post_config
mwr -force 0xF8007000 0x4600E07F

proc st {}   { return [mrd -force -value 0x43C00010] }
proc diag {} { return [expr {([st] >> 16) & 0xFF}] }
proc scnt {} { return [expr {([st] >> 8) & 0xFF}] }
proc cap {}  { return [mrd -force -value 0x43C00014] }
proc cc {}   { mwr -force 0x43C0000C 0x11; after 3; mwr -force 0x43C0000C 0x1 }
proc doinj {fr w m} { mwr -force 0x43C00000 $fr; mwr -force 0x43C00004 $w; mwr -force 0x43C00008 $m
  mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1 }

# --- Phase 1: start + golden init -------------------------------------------
puts "=== P1: start + golden-parity init ==="
set t0 [clock milliseconds]
mwr -force 0x43C0000C 0x1; after 4; mwr -force 0x43C0000C 0x7; after 60; mwr -force 0x43C0000C 0x1
set synced 0; set inited 0
for {set i 0} {$i < 100} {incr i} {
  set s [st]
  if {($s & 1) && !$synced} { set synced 1; puts [format "  synced at +%d ms" [expr {[clock milliseconds]-$t0}]] }
  if {($s >> 16) & 1}      { set inited 1; puts [format "  parity_initialized at +%d ms" [expr {[clock milliseconds]-$t0}]]; break }
  after 50
}
if {!$inited} { puts "  FAIL: golden init did not complete"; }

# --- Phase 2: live diag healthy state ---------------------------------------
after 300
puts "=== P2: live diag (expect 0x41 = init + SM idle + corr-FIFO empty) ==="
foreach n {1 2 3} { puts [format "  scrub_diag = 0x%02X   pcalc_dbg = 0x%02X" [diag] [expr {([cap] >> 24) & 0xFF}]]; after 120 }

# --- Phase 3: clean scan + pass-rate measurement ----------------------------
puts "=== P3: clean scan / scan-pass timing ==="
cc; after 200
foreach n {1 2 3} {
  set c0 [scnt]; set m0 [clock milliseconds]; after 1000
  set c1 [scnt]; set m1 [clock milliseconds]
  set d [expr {($c1 - $c0) & 0xFF}]
  puts [format "  window %d: %d passes in %d ms  (%.1f ms/pass)" $n $d [expr {$m1-$m0}] [expr {$d ? double($m1-$m0)/$d : -1}]]
}
set fl [expr {[cap] & 7}]
puts [format "  captures during clean scanning: flags=0x%X (%s)" $fl [expr {$fl==0 ? {NONE - no false positives} : {UNEXPECTED CAPTURE}}]]

# --- Phase 4: detect + autonomous correct, 6 injections ---------------------
puts "=== P4: inject -> autonomous detect + correct (6 trials) ==="
set det 0; set cor 0
foreach w {5 10 20 31 40 50} {
  cc; after 150
  doinj 0x2000 $w 0x8
  after 500
  set c [cap]; set fl [expr {$c & 7}]
  set far [mrd -force -value 0x43C00018]; set syn [expr {[mrd -force -value 0x43C0001C] & 0x1FFF}]
  set hit [expr {($fl & 2) != 0}]
  if {$hit} { incr det }
  # ack, let scans continue, then confirm the error does not recur (= corrected)
  cc; after 800
  set fl2 [expr {[cap] & 7}]
  set ok [expr {$fl2 == 0}]
  if {$hit && $ok} { incr cor }
  puts [format "  w=%2d: detect=%s (flags=0x%X far=0x%08X syn=0x%04X)  corrected=%s (recheck flags=0x%X)  diag=0x%02X" \
        $w [expr {$hit?"Y":"N"}] $fl $far $syn [expr {$ok?"Y":"N"}] $fl2 [diag]]
}
puts [format "=== RESULT: detected %d/6, corrected %d/6 ===" $det $cor]

# --- Phase 5: steady state after campaign -----------------------------------
after 400
puts [format "=== P5: final scrub_diag = 0x%02X (expect 0x41), scan counter still advancing: %d -> %d ===" \
      [diag] [scnt] [expr {[after 300; scnt]}]]
puts "DONE"
