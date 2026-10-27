# PDS appends to the input script; build.ps1 runs a copy.
add_design "source/conv_parallel.v"
add_constraint "compute.fdc"
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module conv_parallel
synthesize -ads -selected_syn_tool_opt 2
dev_map
