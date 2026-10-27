# Focused report on the same routed database, not another implementation run.
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
report_timing -input_db_file "place_route/hdmi_ddr_ov5640_top_pnr.adf" -force_to_run -report_exception TRUE -from {*u_lane_local_ui*g_camera*mailbox*held*} -to {*u_lane_local_ui*g_camera*mailbox*dst_snapshot*} -max_path 128
