# Explicit routed DB; no source registration or upstream flow commands.
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
report_timing -input_db_file "place_route/hdmi_ddr_ov5640_top_pnr.adf" -force_to_run
