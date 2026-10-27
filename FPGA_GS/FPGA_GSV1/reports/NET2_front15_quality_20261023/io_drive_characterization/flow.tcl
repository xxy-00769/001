add_design probe.v
add_constraint probe.fdc
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module probe
synthesize -ads -selected_syn_tool_opt 2
dev_map
pnr -gplace_seed 5 -optimize_multi_corner_timing -fix_hold_violation
report_timing -report_io_datasheet -to {data*} -max_path 200 -nworst 16 -input_pins TRUE
exit
