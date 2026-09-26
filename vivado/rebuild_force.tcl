open_project $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.xpr
# force the module-reference OOC run to re-synthesize (it was cached from the first build)
# 2026 hardening: no SRLs in the scrubber core (SRL contents are dynamic
# config-frame bits - same self-reference hazard as LUTRAM)
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-shreg_min_size 999} -objects [get_runs scrubber_injection_scrubber_wrapper_0_0_synth_1]
reset_run scrubber_injection_scrubber_wrapper_0_0_synth_1
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
puts "IMPL: [get_property STATUS [get_runs impl_1]]"
