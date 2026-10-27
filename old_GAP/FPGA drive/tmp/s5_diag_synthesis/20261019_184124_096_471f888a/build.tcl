# Isolated application-layer synthesis only: no physical ports or bitstream.
add_design "mes50hp_diag.v"
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module mes50hp_diag
synthesize -ads -selected_syn_tool_opt 2
