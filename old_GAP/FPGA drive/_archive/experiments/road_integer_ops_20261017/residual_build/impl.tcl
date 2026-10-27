# Separate working directory so convolution mapping reports remain intact.
add_design "../source/residual_requant.v"
add_constraint "../compute.fdc"
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module residual_requant
synthesize -ads -selected_syn_tool_opt 2
dev_map
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/road_integer_ops_20261017/source/residual_requant.v"
add_constraint "../compute.fdc"
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module {residual_requant} -top_module residual_requant
synthesize -ads -selected_syn_tool_opt 2 
dev_map 
