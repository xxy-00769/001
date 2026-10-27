# Isolated sensor-colorbar diagnostic. Main sources and generic outputs untouched.
foreach source [glob source/rtl/*.v] {
    add_design $source
}
add_design "../../source/rtl/pll/pll.idf"
add_design "../../source/rtl/wr_fram_buf/wr_fram_buf.idf"
add_design "../../source/rtl/rd_fram_buf/rd_fram_buf.idf"
add_design "../../source/rtl/DDR3_50H/DDR3_50H.idf"
add_constraint "hdmi_ddr_ov5640_top.fdc"
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module hdmi_ddr_ov5640_top
synthesize -ads -selected_syn_tool_opt 2
dev_map
pnr -optimize_multi_corner_timing -fix_hold_violation -fix_hold_violation_iterations 16 -fix_hold_violation_threshold 200 -fix_hold_violation_in_route TRUE -fix_hold_violation_threshold_for_clk_tree 200
report_timing
gen_bit_stream
