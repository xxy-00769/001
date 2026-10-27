module tx_clock_probe(input sys_clk,output rgmii2_txc,rgmii2_tx_ctl,output [3:0] rgmii2_txd);
 wire unused,cfg,ref25,data_clk,clock_clk,locked;
 probe_pll u_cfg_pll(.clkin1(sys_clk),.clkout0(unused),.clkout1(cfg),.clkout2(ref25),.clkout3(data_clk),.clkout4(clock_clk),.pll_lock(locked));
 reg [7:0] pattern=0;always @(posedge data_clk) pattern<=pattern+1'b1;
 reg [4:0] out_data=0;always @(posedge data_clk) out_data<=pattern[4:0];
 reg clk_ff=0;always @(posedge clock_clk) clk_ff<=~clk_ff;
 genvar k;generate for(k=0;k<4;k=k+1) begin: pins
 GTP_OUTBUF pad(.I(out_data[k]),.O(rgmii2_txd[k]));
 end endgenerate
 GTP_OUTBUF ctl_pad(.I(out_data[4]),.O(rgmii2_tx_ctl));
 GTP_OUTBUF clock_pad(.I(clk_ff),.O(rgmii2_txc));
endmodule
