add_design "E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/build/m3_pin_probe/pin_probe.v"
add_design "E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/rtl/network/m3_rgmii_interface.v"
add_design "E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/rtl/network/m3_eth_pll.v"
add_constraint "E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/build/m3_pin_probe/pins.fdc"
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module pin_probe
synthesize -ads -selected_syn_tool_opt 2
dev_map
