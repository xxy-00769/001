# Copy to impl.tcl before running: PDS appends to its input script.
add_design "source/conv_tile.v"
add_constraint "compute.fdc"
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module conv_tile
synthesize -ads -selected_syn_tool_opt 2
dev_map
