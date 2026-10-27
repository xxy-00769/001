module production_io_model_probe(input rgmii2_rxc,rgmii2_rx_ctl,input [3:0] rgmii2_rxd,
 output rgmii2_txc,rgmii2_tx_ctl,output [3:0] rgmii2_txd);
 wire nc,rxv,rxe;wire [7:0] rxd;
 reg [4:0] startup=0; always @(posedge nc) if(!startup[4]) startup<=startup+1'b1;
 reg [7:0] pattern=0;always @(posedge nc) pattern<=pattern+8'd1+rxd+rxv+rxe;
 m36_rgmii_interface phy(.rst(!startup[4]),.rst90(!startup[4]),.rgmii_rxc_phase_d(nc),.rgmii_clk(nc),.rgmii_clk_90p(nc),
 .mac_tx_data_valid(startup[4]),.mac_tx_data(pattern),.mac_rx_error(rxe),.mac_rx_data_valid(rxv),.mac_rx_data(rxd),
 .rgmii_rxc(rgmii2_rxc),.rgmii_rx_ctl(rgmii2_rx_ctl),.rgmii_rxd(rgmii2_rxd),
 .rgmii_txc(rgmii2_txc),.rgmii_tx_ctl(rgmii2_tx_ctl),.rgmii_txd(rgmii2_txd));
endmodule
