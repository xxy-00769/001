# Read-only commands from the existing, vendor-documented preflight.
# No assign, program, reset, erase or register write.
puts "V8_ACCEPTANCE_PROBE_BEGIN"
cfg_set_tcl_break -flag true
cfg_connect -ip 127.0.0.1 -port 65420
cfg_set_cable_property -index 0 -freq 1MHz
cfg_scan_chain
cfg_read_device_property -mode 0 -device_index 0
cfg_read_device_property -mode 3 -device_index 0
cfg_disconnect
puts "V8_ACCEPTANCE_PROBE_FINISHED"
cfg_close
