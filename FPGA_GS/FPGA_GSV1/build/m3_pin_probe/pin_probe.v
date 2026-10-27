module pin_probe(output [3:0] intent_led,input sys_clk,rgmii_rxc,rgmii_rx_ctl,input [3:0] rgmii_rxd, output rgmii_txc,rgmii_tx_ctl,phy_rstn,output [3:0] rgmii_txd);
wire a,b,nc,lk;wire [7:0] d;wire v;
m3_eth_pll pll(.clkin1(rgmii_rxc),.clkout0(a),.clkout1(b),.pll_lock(lk));
m3_rgmii_interface rg(.rst(!lk),.rgmii_rxc_phase_d(b),.rgmii_clk(nc),.rgmii_clk_90p(b),.mac_tx_data_valid(v),.mac_tx_data(d),.mac_rx_error(),.mac_rx_data_valid(v),.mac_rx_data(d),.rgmii_rxc(a),.rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_rxd(rgmii_rxd),.rgmii_txc(rgmii_txc),.rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_txd(rgmii_txd));assign phy_rstn=lk;reg [3:0] cc=0;always @(posedge nc) cc<=cc+1;assign intent_led=cc;endmodule
