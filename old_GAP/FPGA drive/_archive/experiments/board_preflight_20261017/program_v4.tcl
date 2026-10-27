# Restore the user's explicit v4 baseline to volatile FPGA configuration RAM.
# This is NOT the new semantic-road model. No Flash/eFuse/key writes are used.
set bitstream [file normalize [file join [file dirname [info script]] .. .. bitstreams 4_road_markings_filtered_cmos1.sbit]]
if {![file isfile $bitstream]} {error "Missing named v4 baseline"}
puts "V4_PROGRAM_BEGIN"
cfg_set_tcl_break -flag true
cfg_connect -ip 127.0.0.1 -port 65420
cfg_set_cable_property -index 0 -freq 1MHz
cfg_scan_chain
cfg_read_device_property -mode 0 -device_index 0
cfg_assign_file -file $bitstream -device_index 0
cfg_program -device_index 0
cfg_read_device_property -mode 3 -device_index 0
cfg_disconnect
puts "V4_PROGRAM_COMMANDS_FINISHED"
cfg_close
