open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7z010*] 0]
current_hw_device $dev
set_property PROBES.FILE      $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.ltx $dev
set_property FULL_PROBES.FILE $::env(SCRUBBER_ROOT)/bitstream/scrubber_injection_wrapper.ltx $dev
refresh_hw_device $dev
set ila [lindex [get_hw_ilas] 0]
set pv [lindex [get_hw_probes *fecc_syndromevalid -of_objects $ila] 0]
set pf [lindex [get_hw_probes *fecc_far -of_objects $ila] 0]
set_property CONTROL.CAPTURE_MODE BASIC $ila
set_property CAPTURE_COMPARE_VALUE eq1'b1 $pv
if {[file exists /tmp/farmap_trig.txt]} {
  set f [open /tmp/farmap_trig.txt r]; set tv [string trim [read $f]]; close $f
  puts "window trigger: far == $tv"
  set_property TRIGGER_COMPARE_VALUE eq26'h$tv $pf
} else {
  puts "window trigger: first pulse"
  set_property TRIGGER_COMPARE_VALUE eq1'bR $pv
}
set_property CONTROL.TRIGGER_POSITION 0 $ila
set_property CONTROL.DATA_DEPTH 4096 $ila
run_hw_ila $ila
puts "ARMED"
wait_on_hw_ila -timeout 4 $ila
write_hw_ila_data -csv_file /tmp/farmap_out.csv -force [upload_hw_ila_data $ila]
puts "WINDOW_DONE"
