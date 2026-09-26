open_project $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.xpr
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-shreg_min_size 999} -objects [get_runs scrubber_injection_scrubber_wrapper_0_0_synth_1]
reset_run scrubber_injection_scrubber_wrapper_0_0_synth_1
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
puts "SYNTH: [get_property STATUS [get_runs synth_1]]"
