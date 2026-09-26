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

addprobes "*/scrubber/sh_busy"
addprobes "*/scrubber/syndr_handler/*state_reg*"
addprobes "*/scrubber/syndr_handler/sm_last_a*"
addprobes "*/scrubber/syndr_handler/sg_first_a*"
addprobes "*/scrubber/syndr_handler/fifo_empty"
addprobes "*/scrubber/syndr_handler/fifo_read_mem"
addprobes "*/scrubber/syndr_handler/fifo_write_mem"
addprobes "*/scrubber/syndr_handler/mem_write"
addprobes "*/scrubber/syndr_handler/error_timeout_counter*"
addprobes "*/scrubber/syndr_handler/syndromes_in_group*"
addprobes "*/scrubber/syndr_handler/single_frame_subgroup_flag*"
addprobes "*/scrubber/syndr_handler/multiple_frame_subgroup_flag*"
addprobes "*/scrubber/syndr_handler/pass_accepted"
addprobes "*/scrubber/start_parity_calc"
addprobes "*/scrubber/parity_calc_done"
addprobes "*/scrubber/start_error_correction"
addprobes "*/scrubber/error_correction_done"
addprobes "*/scrubber/alg_icap_req_i"
addprobes "*/scrubber/fecc_eccerror_filt"
addprobes "*/scrubber/fecc_syndromevalid"
addprobes "*/scrubber/attr_r*"
addprobes "*/scrubber/alg_dbg*"
addprobes "*/scrubber/skip_active"
addprobes "*/scrubber/fail_cnt*"
puts "TOTAL: $probe_idx probes, $total_bits bits"
save_constraints -force
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
puts "IMPL: [get_property STATUS [get_runs impl_1]]"
