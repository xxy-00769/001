set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
gen_bit_stream -input_db_file "place_route/hdmi_ddr_ov5640_top_pnr.adf" -force_to_run -create_mask_file TRUE
