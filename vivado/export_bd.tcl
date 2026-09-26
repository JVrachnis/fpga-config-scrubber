# Export the block design to a reproducible Tcl script.
# Without this the project cannot be rebuilt from source control: the generated
# BD sources under scrubber2025.gen/ are tool output, not authored input.
open_project $::env(SCRUBBER_ROOT)/vivado/scrubber2025/scrubber2025.xpr
open_bd_design [get_files scrubber_injection.bd]
write_bd_tcl -force -make_local $::env(SCRUBBER_ROOT)/vivado/scrubber_injection_bd.tcl
puts "BD_EXPORT: ok"
