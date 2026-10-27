module tx_clock_probe(input sys_clk,output rgmii2_txc,rgmii2_tx_ctl,output [3:0] rgmii2_txd);
 wire unused, cfg, ref25, data_clk, forward_clk, locked;
 probe_pll u_cfg_pll(.clkin1(sys_clk),.clkout0(unused),.clkout1(cfg),.clkout2(ref25),.clkout3(data_clk),.clkout4(forward_clk),.pll_lock(locked));
 reg [7:0] pattern; always @(posedge data_clk) pattern<=pattern+1'b1;
 wire [4:0] serial;
 genvar k;
 generate for(k=0;k<5;k=k+1) begin: pins
 wire [1:0] pair=k<4?{pattern[k+4],pattern[k]}:{pattern[7],pattern[6]};
 GTP_OSERDES #(.OSERDES_MODE("ODDR"),.WL_EXTEND("FALSE"),.GRS_EN("TRUE"),.LRS_EN("TRUE")) oddr(.DO(serial[k]),.TQ(),.DI({6'd0,pair}),.TI(4'd0),.RCLK(data_clk),.SERCLK(data_clk),.OCLK(1'b0),.RST(!locked));
 if(k<4) GTP_OUTBUF pad(.I(serial[k]),.O(rgmii2_txd[k]));
 else GTP_OUTBUF pad(.I(serial[k]),.O(rgmii2_tx_ctl));
 end endgenerate
 GTP_OUTBUF clock_pad(.I(forward_clk),.O(rgmii2_txc));
endmodule
