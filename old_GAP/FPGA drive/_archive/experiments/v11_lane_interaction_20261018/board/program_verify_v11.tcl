# Authorized v11 RULE TEST download to volatile configuration RAM only.
# No Flash, erase, fallback, key, eFuse, or device-register write commands.
set bitstream [file normalize [file join [file dirname [info script]] .. builds 20261018_130743_866_resume_pnr bitstreams 11_lane_interaction_rule_test_cmos1.sbit]]
set mask [file rootname $bitstream].smsk
if {![file isfile $bitstream] || ![file isfile $mask]} {
    error "Missing v11 bitstream or matching mask"
}
puts "V11_PROGRAM_VERIFY_BEGIN"
cfg_set_tcl_break -flag true
cfg_connect -ip 127.0.0.1 -port 65420
cfg_set_cable_property -index 0 -freq 1MHz
cfg_scan_chain
cfg_read_device_property -mode 0 -device_index 0
cfg_assign_file -file $bitstream -device_index 0
cfg_program -device_index 0
puts "V11_PROGRAM_COMMAND_RETURNED"
cfg_read_device_property -mode 3 -device_index 0
cfg_verify -device_index 0
puts "V11_VERIFY_COMMAND_RETURNED"
cfg_read_device_property -mode 3 -device_index 0
cfg_disconnect
puts "V11_PROGRAM_VERIFY_COMMANDS_FINISHED"
cfg_close
