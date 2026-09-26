open_project $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.xpr
create_bd_design scrubber_injection
update_compile_order -fileset sources_1
create_bd_cell -type module -reference scrubber_wrapper scrubber_wrapper_0
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} [get_bd_cells processing_system7_0]
set_property CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} [get_bd_cells processing_system7_0]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/processing_system7_0/M_AXI_GP0" intc_ip "Auto" Clk_xbar "Auto" Clk_master "Auto" Clk_slave "Auto"} [get_bd_intf_pins scrubber_wrapper_0/S_AXI]
assign_bd_address
set seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces processing_system7_0/Data] -filter {NAME =~ *scrubber*}]
set_property offset 0x43C00000 $seg
set_property range 64K $seg
validate_bd_design
save_bd_design
make_wrapper -files [get_files scrubber_injection.bd] -top
add_files -norecurse [glob $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.gen/sources_1/bd/scrubber_injection/hdl/scrubber_injection_wrapper.v*]
set_property top scrubber_injection_wrapper [current_fileset]
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
puts "IMPL STATUS: [get_property STATUS [get_runs impl_1]]"
open_run impl_1
report_timing_summary -file $::env(SCRUBBER_ROOT)/vivado/scrubber_bd_timing.rpt
puts "WNS: [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]"
puts "BITFILE: [glob -nocomplain $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.runs/impl_1/*.bit]"
