add_design probe_pll.v
add_design top.v
add_constraint probe.fdc
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module tx_clock_probe
synthesize -ads -selected_syn_tool_opt 2
dev_map
pnr -optimize_multi_corner_timing
report_timing -nworst 100 -max_path 200 -input_pins TRUE
