# Shared board-script library (2026-09-03). Source after `connect`.
#
# Register map (0x43C0_0000):
#   0x00 FAR  0x04 word  0x08 mask  0x0C CTRL  0x10 STATUS  0x14 CAPFLAGS
#   0x18 CAP_FAR  0x1C CAP_SYN / debug word (CTRL[10:8] selects)
# CTRL: b0 enable  b1 start  b2 reset  b4 ack-capture  b5 scan_pause
#       b6 HOLD_CORRECTION  b7 TEST_FREEZE  b11 FREEZE_CLK
# STATUS: b0 synced b1 busy b4 ICAP_FREE(released AND parked) b5 ICAP_IDLE
#         [15:8] scan_counter (config-port activity, any client) b16 init
# CAPFLAGS: b1 = capture held; [23:19] recovery word:
#         b19 wd_fires parity  b20..21 init_drops  b22 handoff_timeout  b23 tf_release

set BIT   $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.bit
set PS7   $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/ip/scrubber_injection_processing_system7_0_0/ps7_init.tcl

# --- DAP recovery: the sequence that has worked every time this session ------
proc select_arm {} {
  if {[catch {targets -set -filter {name =~ "ARM*#0"}}]} {
    puts "DAP wedged - recovering"
    catch {targets -set 1}
    catch {rst -system}
    after 2000
    targets -set -filter {name =~ "ARM*#0"}
  }
}

# ps7_init.tcl defines its tables as globals; it must be sourced at file level
source $PS7

proc board_up {} {
  global BIT
  for {set attempt 0} {$attempt < 3} {incr attempt} {
    select_arm
    fpga $BIT
    ps7_init; ps7_post_config
    if {[catch {
      ::_mwr -force 0xF8007000 0x4600E07F
      ::_mwr -force 0x43C0000C 0x1; after 4; ::_mwr -force 0x43C0000C 0x7; after 60; ::_mwr -force 0x43C0000C 0x1
    } err]} {
      puts "board_up: AXI access failed ($err) - DAP recovery, attempt [expr {$attempt+1}]"
      catch {targets -set 1}; catch {rst -system}; after 3000
      continue
    }
    after 1500
    return
  }
  error "board_up: DAP did not recover"
}

# --- every JTAG access retries once through DAP recovery ("Invalid context",
# APB AP transaction error) instead of killing a 30-minute campaign ------------
if {[info commands ::_mrd] eq ""} { rename mrd ::_mrd; rename mwr ::_mwr }
set ::IN_RECOVERY 0
proc hard_recover {} {
  if {$::IN_RECOVERY} { return }
  set ::IN_RECOVERY 1
  puts "JTAG: hard recovery (reconnect + rst -system + reprogram)"
  for {set k 0} {$k < 4} {incr k} {
    catch {disconnect}; after 1500
    if {[catch {connect}]} { after 3000; continue }
    after 1000
    catch {targets -set 1}; catch {rst -system}; after 3000
    if {![catch {board_up}]} { puts "JTAG: recovered on attempt [expr {$k+1}]"; break }
    after 3000
  }
  set ::IN_RECOVERY 0
}
proc mrd args { if {[catch {set r [::_mrd {*}$args]} e]} {
    puts "JTAG: mrd failed ($e)"; hard_recover; set r [::_mrd {*}$args] }; return $r }
proc mwr args { if {[catch {set r [::_mwr {*}$args]} e]} {
    puts "JTAG: mwr failed ($e)"; hard_recover; set r [::_mwr {*}$args] }; return $r }

# --- register helpers ---------------------------------------------------------
# ctrl remembers the last value written so that cc (capture ack) can pulse
# bit4 WITHOUT dropping HOLD/TEST_FREEZE/FREEZE_CLK. An earlier cc that wrote
# a bare 0x1 silently released HOLD_CORRECTION on the first ack, which made
# HOLD look broken (2026-09-03, period3.tcl).
set ::CTRLBASE 0x1
proc ctrl {v}  { set ::CTRLBASE $v; mwr -force 0x43C0000C $v }
proc stat {}   { return [mrd -force -value 0x43C00010] }
proc capf {}   { return [mrd -force -value 0x43C00014] }
proc capfar {} { return [expr {[mrd -force -value 0x43C00018] & 0xFFFFFF}] }
proc free {}   { return [expr {([stat]>>4)&1}] }
proc busy {}   { return [expr {([stat]>>1)&1}] }
proc init {}   { return [expr {([stat]>>16)&1}] }
proc sc {}     { return [expr {([stat]>>8)&0xFF}] }
proc wdpar {}  { return [expr {([capf]>>19)&1}] }
proc initdrops {} { return [expr {([capf]>>20)&3}] }
proc hto {}    { return [expr {([capf]>>22)&1}] }
proc tfrel {}  { return [expr {([capf]>>23)&1}] }
proc cc {}     { set b $::CTRLBASE; mwr -force 0x43C0000C [expr {$b | 0x10}]; after 3; mwr -force 0x43C0000C $b }
proc drain {}  { for {set i 0} {$i<60} {incr i} { if {[capf]&2} { cc } else { break } } }

# --- freeze / thaw with the hand-off ASSERTED, not assumed -------------------
proc wait_free {ms} { set t [clock milliseconds]
  while {[clock milliseconds]-$t < $ms} { if {[free]} { return 1 }; after 5 }; return 0 }

# returns 1 on success; on failure leaves the board unfrozen and returns 0
proc freeze {} {
  ctrl 0x81
  if {![wait_free 500]} {
    puts "HANDOFF FAILED (timeout=[hto] tf_release=[tfrel] busy=[busy]) - not freezing"
    ctrl 0x1; after 200
    return 0
  }
  ctrl 0x881; after 20
  return 1
}
proc thaw {{base 0x1}} { ctrl $base; after 100 }

# single-bit XOR injection with CTRL base held throughout.
#
# Raise REQUEST (bit1) first and START (bit2) only after the arbiter has had
# time to grant. Writing both in one AXI word works for the first injection
# after a hand-off and fails for every later one under the same freeze
# (pair.tcl: second injection lost 15/16; pair2.tcl: request-then-start 8/8).
# The arbiter's rotating priority takes a variable number of cycles to reach
# the injector channel and the injector's Start handling races it.
proc inject {base far word mask} {
  mwr -force 0x43C00000 $far; mwr -force 0x43C00004 $word; mwr -force 0x43C00008 $mask
  ctrl $base; after 3
  ctrl [expr {$base | 0x2}]; after 20          ;# request, wait for grant
  ctrl [expr {$base | 0x6}]; after 30          ;# start
  ctrl $base; after 20 }

# poll for a capture at exactly $target; returns ms-to-first-hit or -1
proc first_hit {target ms} {
  set t [clock milliseconds]
  while {[clock milliseconds]-$t < $ms} {
    if {[capf]&2} {
      if {[capfar] == $target} { return [expr {[clock milliseconds]-$t}] }
      cc }
    after 8 }
  return -1 }

# count captures at $target over a window (do not break on first)
proc hits_in {target ms} {
  set t [clock milliseconds]; set n 0
  while {[clock milliseconds]-$t < $ms} {
    if {[capf]&2} { if {[capfar] == $target} { incr n }; cc }
    after 8 }
  return $n }

# every distinct captured FAR over a window
proc collect {ms} { set t [clock milliseconds]; set S {}
  while {[clock milliseconds]-$t < $ms} {
    if {[capf]&2} { set f [capfar]
      if {[lsearch -exact $S $f] < 0} { lappend S $f }; cc }
    after 8 }
  return $S }

# live core word (Rev. 1.11): CTRL bit12 selects it at 0x1C, but the read mux
# only leaves the historical overlay when CTRL[10:8] is nonzero - so set both.
# [7:0] wd_fires [8] sh_busy [9] alg req [10] alg grant [11] pcalc req
# [12] pcalc grant [13] icap_busy [14] init [15] poisoned [17:16] scan_state
# [23:18] wd_cnt(23:18) [31:24] alg_dbg
proc live {} { set b $::CTRLBASE
  mwr -force 0x43C0000C [expr {$b | 0x1200}]; set v [mrd -force -value 0x43C0001C]
  mwr -force 0x43C0000C $b; return $v }
proc livestr {v} {
  set st [lindex {IDLE ARB GRANT END} [expr {($v>>14)&3}]]
  return [format "wd=%d skip=%d sh=%d alg=%d/%d pc=%d/%d inj=%d/%d icap=%d init=%d poi=%d scan=%d arb=%s sel=%d 1hot=%03b grant=%03b g=%d alg_dbg=%02x" \
    [expr {$v&0x7}] [expr {($v>>3)&1}] [expr {($v>>4)&1}] [expr {($v>>5)&1}] [expr {($v>>6)&1}] [expr {($v>>7)&1}] [expr {($v>>8)&1}] \
    [expr {($v>>25)&1}] [expr {($v>>26)&1}] [expr {($v>>9)&1}] [expr {($v>>10)&1}] [expr {($v>>11)&1}] [expr {($v>>12)&3}] \
    $st [expr {($v>>16)&3}] [expr {($v>>18)&7}] [expr {($v>>21)&7}] [expr {($v>>24)&1}] [expr {($v>>27)&0x1F}]] }

proc wdf {}     { return [expr {[live] & 0x7}] }
# --- frame readback (Rev. 1.14): a mask-0 injection captures the frame into the
# injector's buffer without changing it; CTRL bit13 + nonzero CTRL[10:8]
# exposes buffer word 0x04 at 0x1C.  readframe returns 101 words.
proc readframe {far {base 0x1}} {
  inject $base $far 0 0x0
  set out {}
  for {set w 0} {$w < 101} {incr w} {
    mwr -force 0x43C00004 $w
    mwr -force 0x43C0000C [expr {$base | 0x2200}]
    lappend out [mrd -force -value 0x43C0001C]
  }
  mwr -force 0x43C0000C $base
  return $out }
proc framediff {a b} { set d {}
  for {set w 0} {$w < 101} {incr w} { set x [expr {[lindex $a $w] ^ [lindex $b $w]}]
    if {$x} { lappend d [format "w%d:0x%08X" $w $x] } }
  return $d }

proc recword {} { return [format "wd=%d drops=%d hto=%d rel=%d init=%d" [wdpar] [initdrops] [hto] [tfrel] [init]] }
