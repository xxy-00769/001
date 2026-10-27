module local_io(input rgmii2_rxc,input [3:0] rgmii2_rxd,input rgmii2_rx_ctl,
 output rgmii2_txc,output [3:0] rgmii2_txd,output rgmii2_tx_ctl);
 wire phase,unused_phase,locked,nc,rxv,rxe;wire [7:0] rxd;
 m3_eth_pll pll(.clkin1(rgmii2_rxc),.clkout0(phase),.clkout1(unused_phase),.pll_lock(locked));
 reg [7:0] txd=0;reg txv=0;
 always @(posedge nc) begin txd<=txd+1'b1+(rxv ? rxd:8'd0);txv<=locked && !rxe;end
 m364_e1_rgmii phy(.rst(!locked),.rgmii_rxc_phase_d(nc),.rgmii_clk(nc),.rgmii_clk_90p(unused_phase),
 .mac_tx_data_valid(txv),.mac_tx_data(txd),.mac_rx_error(rxe),.mac_rx_data_valid(rxv),.mac_rx_data(rxd),
 .rgmii_rxc(phase),.rgmii_rx_ctl(rgmii2_rx_ctl),.rgmii_rxd(rgmii2_rxd),
 .rgmii_txc(rgmii2_txc),.rgmii_tx_ctl(rgmii2_tx_ctl),.rgmii_txd(rgmii2_txd));
endmodule
