# Inspect mapped exception coverage before spending time on routing.
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
report_timing -input_db_file "device_map/hdmi_ddr_ov5640_top_map.adf" -force_to_run
