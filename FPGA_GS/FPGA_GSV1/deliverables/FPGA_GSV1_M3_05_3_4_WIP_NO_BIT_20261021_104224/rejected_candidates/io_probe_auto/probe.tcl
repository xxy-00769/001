add_design probe.v
add_constraint probe.fdc
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module probe
synthesize -ads
dev_map
pnr
report_timing
