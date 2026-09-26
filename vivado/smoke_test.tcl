open_project $::env(SCRUBBER_ROOT)/vivado/bram_test/bram_test.xpr
upgrade_ip [get_ips *] -quiet
report_ip_status
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
puts "IMPL STATUS: [get_property STATUS [get_runs impl_1]]"
puts "PROGRESS: [get_property PROGRESS [get_runs impl_1]]"
