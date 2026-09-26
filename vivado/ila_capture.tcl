open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7z010*] 0]
current_hw_device $dev
set_property PROBES.FILE      $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.ltx $dev
set_property FULL_PROBES.FILE $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.ltx $dev
refresh_hw_device $dev
set ila [lindex [get_hw_ilas] 0]
puts "ILA: $ila  probes:"
foreach p [get_hw_probes -of_objects $ila] { puts "  [get_property NAME $p] ([get_property WIDTH $p])" }
# trigger: rising edge of start_error_correction
set trig [lindex [get_hw_probes *start_error_correction* -of_objects $ila] 0]
set_property TRIGGER_COMPARE_VALUE eq1'bR $trig
set_property CONTROL.TRIGGER_POSITION 128 $ila
set_property CONTROL.DATA_DEPTH 4096 $ila
run_hw_ila $ila
puts "armed; waiting for trigger..."
if {[catch {wait_on_hw_ila -timeout 3 $ila} err]} {
  puts "TRIGGER TIMEOUT (60s): $err  -> falling back to trigger_now"
  run_hw_ila -trigger_now $ila
  wait_on_hw_ila $ila
}
set d [upload_hw_ila_data $ila]
write_hw_ila_data -csv_file /tmp/ila_capture.csv -force $d
puts "CSV written"
