open_project $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.xpr
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
puts "IMPL: [get_property STATUS [get_runs impl_1]]"
puts "WNS: [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]"
