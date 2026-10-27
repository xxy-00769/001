add_design "E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/work/M3_06_front15_txdet1/reports/local_io/local_io.v"
add_design "E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/work/M3_06_front15_txdet1/rtl/network/m3_eth_pll.v"
add_design "E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/work/M3_06_front15_txdet1/rtl/network/m364_e1_rgmii.v"
add_constraint local_io.fdc
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module local_io
synthesize -ads -selected_syn_tool_opt 2
dev_map
pnr -gplace_seed 5 -optimize_multi_corner_timing -fix_hold_violation
report_timing -nworst 32 -max_path 1000 -input_pins true
exit
