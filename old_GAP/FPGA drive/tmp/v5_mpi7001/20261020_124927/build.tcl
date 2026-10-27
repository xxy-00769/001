# ============================================================================
#  HDMI_DDR3_OV5640  -  Pango Design Suite batch flow  (TEMPLATE)
#  Target : PGL50H-6FBG484  (Logos family)
#  Tool   : PDS 2022.2-SP6.1
#
#  DO NOT run this file directly.
#  build.bat copies it to impl.tcl and runs that, because pds_shell APPENDS
#  its own absolute-path flow to whatever script file it is given.
#
#  All paths are RELATIVE, so this project directory can be moved or copied
#  anywhere without editing this file.
# ============================================================================

# ---- Design sources (Verilog) ----------------------------------------------
add_design "source/rtl/hdmi_ddr_ov5640_top.v"
add_design "source/rtl/img_proc.v"
add_design "source/rtl/video_mode_key.v"
add_design "source/rtl/video_capture_status.v"
add_design "source/rtl/lane_detect.v"
add_design "source/rtl/zebra_detect.v"
add_design "source/rtl/zebra_overlay.v"
add_design "source/rtl/lane_geometry.v"
add_design "source/rtl/adas_overlay.v"
add_design "source/rtl/adas_packet.v"
add_design "source/rtl/adas_test_pattern.v"
add_design "source/rtl/cmos_8_16bit.v"
add_design "source/rtl/fram_buf.v"
add_design "source/rtl/frame_buffer_owner.v"
add_design "source/rtl/i2c_com.v"
add_design "source/rtl/iic_dri.v"
add_design "source/rtl/ms72xx_ctl.v"
add_design "source/rtl/ms7200_ctl.v"
add_design "source/rtl/ms7210_ctl.v"
add_design "source/rtl/power_on_delay.v"
add_design "source/rtl/rd_buf.v"
add_design "source/rtl/rd_ctrl.v"
add_design "source/rtl/reg_config.v"
add_design "source/rtl/sync_vg.v"
add_design "source/rtl/mpi7001_timing.v"
add_design "source/rtl/pll_mpi7001.v"
add_design "source/rtl/wr_buf.v"
add_design "source/rtl/wr_cmd_trans.v"
add_design "source/rtl/wr_ctrl.v"
add_design "source/rtl/wr_rd_ctrl_top.v"

# ---- IP cores (.idf) -------------------------------------------------------
add_design "source/rtl/pll/pll.idf"
add_design "source/rtl/wr_fram_buf/wr_fram_buf.idf"
add_design "source/rtl/rd_fram_buf/rd_fram_buf.idf"
add_design "source/rtl/DDR3_50H/DDR3_50H.idf"

# ---- Constraints -----------------------------------------------------------
add_constraint "hdmi_ddr_ov5640_top.fdc"

# ---- Flow ------------------------------------------------------------------
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module hdmi_ddr_ov5640_top
synthesize -ads -selected_syn_tool_opt 2
dev_map
# Repair short DDR3/pixel paths in both corners without relaxing constraints.
pnr -optimize_multi_corner_timing -fix_hold_violation -fix_hold_violation_iterations 24 -fix_hold_violation_threshold 350 -fix_hold_violation_in_route TRUE -fix_hold_violation_threshold_for_clk_tree 200
report_timing
gen_bit_stream
