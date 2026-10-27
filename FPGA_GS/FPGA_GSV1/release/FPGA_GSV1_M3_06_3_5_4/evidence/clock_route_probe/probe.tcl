add_design probe.v
add_design ../../rtl/board/m364_ref_dividers.v
add_design ../../rtl/display/m31_pixel_pll.v
add_design ../../rtl/network/m3_eth_pll.v
add_design ../../rtl/network/m364_e1_rgmii.v
add_design ../../vendor/DDR3_50H/rtl/pll/ipsxb_ddrphy_pll_v1_0.v
add_constraint probe.fdc
set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484
compile -top_module clock_route_probe
synthesize -ads -selected_syn_tool_opt 2
dev_map
pnr -optimize_multi_corner_timing
report_timing