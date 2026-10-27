add_design "top.v"
add_design "io.v"
add_constraint "io.fdc"
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module io_probe
synthesize -ads -selected_syn_tool_opt 2
dev_map
pnr -gplace_seed 5 -fix_hold_violation -fix_hold_violation_iterations 4 -fix_hold_violation_in_route TRUE
report_timing
