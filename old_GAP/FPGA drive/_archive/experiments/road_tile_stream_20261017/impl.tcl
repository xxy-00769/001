# PDS appends to the input script; build.ps1 executes a copy.
add_design "source/conv_cached.v"
add_design "source/conv_stream_probe.v"
add_constraint "compute.fdc"
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module conv_stream_probe
synthesize -ads -selected_syn_tool_opt 2
dev_map
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/road_tile_stream_20261017/source/conv_cached.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/road_tile_stream_20261017/source/conv_stream_probe.v"
add_constraint "compute.fdc"
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module {conv_stream_probe} -top_module conv_stream_probe
synthesize -ads -selected_syn_tool_opt 2 
dev_map 
