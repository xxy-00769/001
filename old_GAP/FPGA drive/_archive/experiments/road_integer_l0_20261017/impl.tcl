# Copy to impl.tcl: PDS appends generated flow text to its input script.
add_design "source/layer0_params.v"
add_design "source/layer0_tile.v"
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module layer0_tile
synthesize -ads -selected_syn_tool_opt 2
dev_map
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/road_integer_l0_20261017/source/layer0_params.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/road_integer_l0_20261017/source/layer0_tile.v"
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module {layer0_tile} -top_module layer0_tile
synthesize -ads -selected_syn_tool_opt 2 
dev_map 
