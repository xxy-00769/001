module io_probe(input sys_clk,input rgmii2_rxc,rgmii2_rx_ctl,input [3:0] rgmii2_rxd,
 output rgmii2_txc,rgmii2_tx_ctl,output [3:0] rgmii2_txd);
 wire nc,rv,re;wire [7:0] data;reg [7:0] count=0;reg [3:0] reset_count=0;
 always @(posedge sys_clk) if(reset_count!=15) reset_count<=reset_count+1'b1;
 always @(posedge nc) count<=count+data+{7'd0,rv^re};
 m36_rgmii_probe io(.rst(reset_count!=15),.rst90(reset_count!=15),.rgmii_rxc_phase_d(nc),.rgmii_clk(nc),.rgmii_clk_90p(nc),
 .mac_tx_data_valid(count[7]),.mac_tx_data(count),.mac_rx_error(re),.mac_rx_data_valid(rv),.mac_rx_data(data),
 .rgmii_rxc(rgmii2_rxc),.rgmii_rx_ctl(rgmii2_rx_ctl),.rgmii_rxd(rgmii2_rxd),
 .rgmii_txc(rgmii2_txc),.rgmii_tx_ctl(rgmii2_tx_ctl),.rgmii_txd(rgmii2_txd));
endmodule
