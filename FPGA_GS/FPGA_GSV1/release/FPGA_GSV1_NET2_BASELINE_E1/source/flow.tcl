foreach f [glob rtl/*.v] {add_design $f}
add_constraint constraints/net2.fdc
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module net2_official_baseline
synthesize -ads -selected_syn_tool_opt 2
dev_map
pnr -optimize_multi_corner_timing
report_timing -nworst 50 -max_path 200 -input_pins TRUE
gen_bit_stream
