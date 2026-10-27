add_design E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/work/M3_06_fix_3_5_3/rtl/network/m36_rgmii_interface.v
add_design top.v
add_constraint probe.fdc
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module production_io_model_probe
synthesize -ads -selected_syn_tool_opt 2
dev_map
pnr -optimize_multi_corner_timing -fix_hold_violation -fix_hold_violation_in_route TRUE
report_timing -nworst 100 -max_path 150 -input_pins TRUE -to {rgmii2_txc rgmii2_txd* rgmii2_tx_ctl}
