create_project -force scrubber2025 $::env(SCRUBBER_ROOT)/vivado/scrubber2025 -part xc7z010clg400-1
set_property board_part digilentinc.com:zybo-z7-10:part0:1.0 [current_project]
set R $::env(SCRUBBER_ROOT)/rtl
add_files [list $R/v1.8/log2_pkg.vhd $R/v1.8/icape_common.vhd $R/v1.8/scrubber_ip_pkg.vhd $R/v1.8/scrubber_ip.vhd $R/v1.8/scrubber_ip_wrapper.vhd $R/v1.8/scrubber_wrapper.vhd]
foreach d {mem_blocks golden_parity_mem calc_parity_mem parity_calculator syndrome_handler edc_algorithm icap_controller icap_arbiter fault_injection} {
  foreach f [glob -nocomplain $R/modules/$d/*.vhd] {
    if {![string match *_tb* $f] && ![string match *_OLD* $f]} { add_files $f }
  }
}
set_property top scrubber_wrapper [current_fileset]
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
puts "SYNTH STATUS: [get_property STATUS [get_runs synth_1]]"
open_run synth_1
report_utilization -file $::env(SCRUBBER_ROOT)/vivado/scrubber_util.rpt
puts "UTIL REPORT WRITTEN"
