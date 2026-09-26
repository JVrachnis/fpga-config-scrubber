# Capture the device's frame-address sequence via qualified ILA sampling:
# one sample per SYNDROMEVALID pulse -> 4096 frames per window.
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
# window 1: trigger on the first pulse, qualified capture
set_property CONTROL.CAPTURE_MODE BASIC $ila
set_property CAPTURE_COMPARE_VALUE eq1'b1 $pv
set_property TRIGGER_COMPARE_VALUE eq1'bR $pv
set_property CONTROL.TRIGGER_POSITION 0 $ila
set_property CONTROL.DATA_DEPTH 4096 $ila
run_hw_ila $ila
puts "ARMED_W1"
# the DUT is started externally now; wait for fill
wait_on_hw_ila -timeout 3 $ila
write_hw_ila_data -csv_file /tmp/farmap_w1.csv -force [upload_hw_ila_data $ila]
puts "W1 done"
# find a late FAR value from w1 to use as window-2 trigger: read csv quickly in tcl? do in shell later.
# window 2: trigger on a FAR value near the end of window 1 (passed via env file)
set f [open /tmp/farmap_trig.txt r]; set trigval [string trim [read $f]]; close $f
set_property TRIGGER_COMPARE_VALUE eq1'b1 $pv
set_property TRIGGER_COMPARE_VALUE eq26'h$trigval $pf
set_property CONTROL.TRIGGER_POSITION 0 $ila
run_hw_ila $ila
puts "ARMED_W2"
wait_on_hw_ila -timeout 2 $ila
write_hw_ila_data -csv_file /tmp/farmap_w2.csv -force [upload_hw_ila_data $ila]
puts "W2 done"
