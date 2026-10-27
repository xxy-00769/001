set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
pnr -input_db_file "device_map/hdmi_ddr_ov5640_top_map.adf" -force_to_run -optimize_multi_corner_timing -fix_hold_violation -fix_hold_violation_iterations 16 -fix_hold_violation_threshold 200 -fix_hold_violation_in_route TRUE -fix_hold_violation_threshold_for_clk_tree 200
