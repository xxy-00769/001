# Isolated v11 RULE TEST on CMOS1; no programmer or Flash commands.
foreach source [glob source/rtl/*.v] {
    add_design $source
}
add_design "source/rtl/pll/pll.idf"
add_design "source/rtl/wr_fram_buf/wr_fram_buf.idf"
add_design "source/rtl/rd_fram_buf/rd_fram_buf.idf"
add_design "source/rtl/DDR3_50H/DDR3_50H.idf"
add_constraint "hdmi_ddr_ov5640_top.fdc"
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module hdmi_ddr_ov5640_top
synthesize -ads -selected_syn_tool_opt 2
dev_map
pnr -optimize_multi_corner_timing -fix_hold_violation -fix_hold_violation_iterations 16 -fix_hold_violation_threshold 200 -fix_hold_violation_in_route TRUE -fix_hold_violation_threshold_for_clk_tree 200
report_timing
gen_bit_stream
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/adas_overlay.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/adas_packet.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/adas_test_pattern.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/cmos_8_16bit.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/fram_buf.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/hdmi_ddr_ov5640_top.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/i2c_com.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/iic_dri.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/img_proc.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/lane_button_events.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/lane_change_control.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/lane_change_overlay.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/lane_detect.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/lane_geometry.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/lane_local_ui.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/lane_rule_test_source.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/lane_snapshot_cdc.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/ms7200_ctl.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/ms7210_ctl.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/ms72xx_ctl.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/power_on_delay.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/rd_buf.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/rd_ctrl.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/reg_config.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/sync_vg.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/wr_buf.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/wr_cmd_trans.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/wr_ctrl.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/wr_rd_ctrl_top.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/zebra_detect.v"
add_design "E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/zebra_overlay.v"
add_design E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/pll/pll.idf
add_design E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/wr_fram_buf/wr_fram_buf.idf
add_design E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/rd_fram_buf/rd_fram_buf.idf
add_design E:/FPGA drive/HDMI_DDR3_OV5640/experiments/v11_lane_interaction_20261018/builds/20261018_114715_310_rule_test/source/rtl/DDR3_50H/DDR3_50H.idf
add_constraint "hdmi_ddr_ov5640_top.fdc"
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module {hdmi_ddr_ov5640_top} -top_module hdmi_ddr_ov5640_top
synthesize -ads -selected_syn_tool_opt 2 
dev_map 
