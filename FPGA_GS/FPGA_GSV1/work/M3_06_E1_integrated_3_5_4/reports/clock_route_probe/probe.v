`timescale 1ns/1ps
// Resource/routing feasibility only; not a downloadable network experiment.
module clock_route_probe(input clk_50m,net1_rxc,rgmii_rxc,rgmii_rx_ctl,
 input [3:0] rgmii_rxd,output rgmii_txc,rgmii_tx_ctl,output [3:0] rgmii_txd,
 output [7:0] monitor);
 wire cfg,cam,ready,pixel,n10,n11,n20,n21,nc,dr0,dr1,dl0,dl1;
 m364_ref_dividers refs(.clkin1(clk_50m),.cfg_clk(cfg),.camera_clk(cam),.ready(ready));
 m31_pixel_pll display_pll(.clkin1(clk_50m),.clkout0(pixel),.pll_lock());
 m3_eth_pll port1_pll(.clkin1(net1_rxc),.clkout0(n10),.clkout1(n11),.pll_lock());
 m3_eth_pll port2_pll(.clkin1(rgmii_rxc),.clkout0(n20),.clkout1(n21),.pll_lock());
 ipsxb_ddrphy_pll_v1_0 #(.CLKIN_FREQ(50.0),.STATIC_RATIOI(1),.STATIC_RATIOF(16)) ddr0(
 .clkin1(clk_50m),.clkout0_gate(1'b1),.pll_rst(1'b0),.clkout0(),.clkout1(dr0),.pll_lock(dl0));
 ipsxb_ddrphy_pll_v1_0 #(.CLKIN_FREQ(50.0),.STATIC_RATIOI(1),.STATIC_RATIOF(16)) ddr1(
 .clkin1(clk_50m),.clkout0_gate(1'b1),.pll_rst(1'b0),.clkout0(),.clkout1(dr1),.pll_lock(dl1));
 reg [7:0] data=0;always @(posedge nc) data<=data+1'b1;
 m364_e1_rgmii physical(.rst(1'b0),.rgmii_rxc_phase_d(n21),.rgmii_clk(nc),.rgmii_clk_90p(1'b0),
 .mac_tx_data_valid(data[7]),.mac_tx_data(data),.rgmii_rxc(n20),
 .rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_rxd(rgmii_rxd),.mac_rx_error(),.mac_rx_data_valid(),.mac_rx_data(),
 .rgmii_txc(rgmii_txc),.rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_txd(rgmii_txd));
 reg a=0,b=0,c=0,d=0,e=0,f=0,g=0;
 always @(posedge cfg) a<=!a;always @(posedge cam) b<=!b;
 always @(posedge pixel) c<=!c;always @(posedge n10) d<=!d;
 always @(posedge n11) e<=!e;always @(posedge dr0) f<=!f;
 always @(posedge dr1) g<=!g;
 assign monitor={a,b,c,d,e,f,g,ready^dl0^dl1};
endmodule
