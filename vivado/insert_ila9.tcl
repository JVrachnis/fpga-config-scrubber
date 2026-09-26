open_project $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.xpr
open_run synth_1 -name netlist_1

set probe_idx 0
set total_bits 0
proc addprobes {pat} {
  global probe_idx total_bits
  set nets [get_nets -hier -quiet -filter "NAME =~ \"$pat\""]
  if {[llength $nets] == 0} { puts "MISS: $pat"; return }
  array set groups {}
  foreach n $nets {
    set nm [get_property NAME $n]
    # skip synth LUT intermediates
    if {[string match "*_n_0" $nm] || [regexp {_i_[0-9]+$} $nm] || [regexp {_i_[0-9]+\[} $nm]} { continue }
    regexp {^(.*?)(\[[0-9]+\])?$} $nm -> base idx
    lappend groups($base) $nm
  }
  set bases [lsort [array names groups]]
  if {[llength $bases] == 0} { puts "MISS(all filtered): $pat"; return }
  # connect only the first group (hierarchy aliases are electrically identical)
  set base [lindex $bases 0]
  set lst $groups($base)
  if {[llength $lst] > 1} {
    set lst [lsort -command {apply {{a b} {
      regexp {\[([0-9]+)\]$} $a -> ia; regexp {\[([0-9]+)\]$} $b -> ib
      expr {$ia - $ib} }}} $lst]
  }
  set w [llength $lst]
  if {$total_bits + $w > 400} { puts "SKIP(full): $base ($w)"; return }
  if {$probe_idx == 0} {
    set port [get_debug_ports u_ila_0/probe0]
  } else {
    create_debug_port u_ila_0 probe
    set port [get_debug_ports u_ila_0/probe$probe_idx]
  }
  set_property PROBE_TYPE DATA_AND_TRIGGER $port
  set_property port_width $w $port
  connect_debug_port $port [get_nets $lst]
  puts "PROBE$probe_idx: $base  width=$w"
  incr probe_idx
  incr total_bits $w
}

create_debug_core u_ila_0 ila
set_property C_DATA_DEPTH 4096      [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false      [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false    [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 1  [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
set clknet [lindex [get_nets -hier -filter {NAME =~ "*FCLK_CLK0" && NAME !~ "*u_ila*" && NAME !~ "*dbg_hub*"}] 0]
puts "CLOCK NET: $clknet"
connect_debug_port u_ila_0/clk [get_nets $clknet]

addprobes "*/syndr_handler/start_error_correction"
addprobes "*/syndr_handler/single_frame_in_subgr*"
addprobes "*/syndr_handler/subgroup*"
addprobes "*/algorithm/icap_if/correct_using_parity"
addprobes "*/algorithm/icap_if/merge_idx*"
addprobes "*/algorithm/icap_if/merge_ph*"
addprobes "*/algorithm/icap_if/merge_done"
addprobes "*/algorithm/icap_if/merge_word*"
addprobes "*/algorithm/icap_if/calc_word_rd_data*"
addprobes "*/algorithm/icap_if/i_calc_word_rd_addr*"
addprobes "*/algorithm/icap_if/calc_subgroup_rd_addr*"
addprobes "*/algorithm/icap_if/frame_buffer_rddata*"
addprobes "*/algorithm/icap_if/frame_buffer_write"
addprobes "*/algorithm/icap_if/calc_read_grant"
puts "TOTAL: $probe_idx probes, $total_bits bits"
save_constraints -force
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
puts "IMPL: [get_property STATUS [get_runs impl_1]]"
