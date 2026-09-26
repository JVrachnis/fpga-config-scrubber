# arm ILA on inject_start rising, wait up to 90 s, upload CSV to $::env(ILA_CSV)
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7z010*] 0]
current_hw_device $dev
set_property PROBES.FILE      $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.ltx $dev
set_property FULL_PROBES.FILE $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.ltx $dev
refresh_hw_device $dev
set ila [lindex [get_hw_ilas] 0]
set trig [lindex [get_hw_probes *inject_start* -of_objects $ila] 0]
set_property TRIGGER_COMPARE_VALUE eq1'bR $trig
set_property CONTROL.TRIGGER_POSITION 300 $ila
set_property CONTROL.DATA_DEPTH 4096 $ila
run_hw_ila $ila
set f [open /tmp/ila_armed w]; puts $f armed; close $f
puts "armed"
if {[catch {wait_on_hw_ila -timeout 2 $ila} err]} { puts "TRIGGER TIMEOUT"; exit 1 }
set d [upload_hw_ila_data $ila]
write_hw_ila_data -csv_file $::env(ILA_CSV) -force $d
puts "CSV written $::env(ILA_CSV)"
