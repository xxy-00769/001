# Copy to impl.tcl before running: PDS appends generated flow text to the script.
add_design "source/road_thumbnail.v"
add_design "source/road_input_buffer.v"
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module road_input_buffer
synthesize -ads -selected_syn_tool_opt 2
dev_map
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/road_input_20261017/source/road_thumbnail.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/road_input_20261017/source/road_input_buffer.v"
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module {road_input_buffer} -top_module road_input_buffer
synthesize -ads -selected_syn_tool_opt 2 
dev_map 
