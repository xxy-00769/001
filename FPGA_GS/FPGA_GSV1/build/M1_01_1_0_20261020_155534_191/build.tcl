# M1-01, PDS 2022.2-SP6.4; run scripts/build.ps1 for isolated outputs.
add_design "rtl/board/fpga_gsv1_top.v"
add_design "rtl/board/hdmi_tx_config.v"
add_design "rtl/board/m1_keys.v"
add_design "rtl/capture/capture_pipe.v"
add_design "rtl/frame/dual_ddr_arbiter.v"
add_design "rtl/display/m1_osd.v"
add_design "rtl/display/m1_view_select.v"
add_design "rtl/reuse/cmos_8_16bit.v"
add_design "rtl/reuse/reg_config.v"
add_design "rtl/reuse/i2c_com.v"
add_design "rtl/reuse/power_on_delay.v"
add_design "rtl/reuse/iic_dri.v"
add_design "rtl/reuse/ms7210_ctl.v"
add_design "rtl/reuse/pll_mpi7001.v"
add_design "rtl/reuse/mpi7001_timing.v"
add_design "rtl/reuse/video_capture_status.v"
add_design "rtl/reuse/frame_buffer_owner.v"
add_design "rtl/reuse/fram_buf.v"
add_design "rtl/reuse/wr_buf.v"
add_design "rtl/reuse/rd_buf.v"
add_design "rtl/reuse/wr_ctrl.v"
add_design "rtl/reuse/rd_ctrl.v"
add_design "rtl/reuse/wr_cmd_trans.v"
add_design "rtl/reuse/wr_rd_ctrl_top.v"
add_design "vendor/DDR3_50H/DDR3_50H.idf"
add_design "vendor/wr_fram_buf/wr_fram_buf.idf"
add_design "vendor/rd_fram_buf/rd_fram_buf.idf"
add_constraint "constraints/mes50hp.fdc"
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module fpga_gsv1_top
synthesize -ads -selected_syn_tool_opt 2
dev_map
pnr -gplace_seed 5 -enable_route_constraint_iterate -route_constraint_iterate_times 3 -route_constraint_slack 0.05 -optimize_multi_corner_timing -fix_hold_violation -fix_hold_violation_iterations 24 -fix_hold_violation_threshold 350 -fix_hold_violation_in_route TRUE -fix_hold_violation_threshold_for_clk_tree 200
report_timing
gen_bit_stream
