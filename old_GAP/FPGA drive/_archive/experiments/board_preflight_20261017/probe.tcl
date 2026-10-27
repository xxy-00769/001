# PDS 2022.2-SP6.1 Fabric Configuration User Guide, sections 4.5.1/4.5.2.
# Read-only JTAG probe: never assign, program, erase, reset, or write registers.
puts "PREFLIGHT_BEGIN"
cfg_set_tcl_break -flag true
cfg_connect -ip 127.0.0.1 -port 65420
cfg_set_cable_property -index 0 -freq 1MHz
cfg_scan_chain
cfg_read_device_property -mode 0 -device_index 0
cfg_read_device_property -mode 3 -device_index 0
cfg_disconnect
puts "PREFLIGHT_COMMANDS_FINISHED"
# The host must inspect the vendor log too; exit status alone is insufficient.
cfg_close
