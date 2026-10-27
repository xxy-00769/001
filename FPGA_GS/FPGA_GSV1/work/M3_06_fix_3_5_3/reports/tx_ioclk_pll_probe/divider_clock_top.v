module tx_clock_probe(input sys_clk,output rgmii2_txc,rgmii2_tx_ctl,output [3:0] rgmii2_txd);
 wire cfg,ref25,raw_clk,forward_clk,io_clk,half_raw,half_clk,locked;
 probe_pll u_cfg_pll(.clkin1(sys_clk),.clkout0(raw_clk),.clkout0_ext(forward_clk),.clkout1(cfg),.clkout2(ref25),.clkout3(),.clkout4(),.pll_lock(locked));
 GTP_IOCLKBUF #(.GATE_EN("FALSE")) iobuf(.CLKIN(raw_clk),.DI(1'b1),.CLKOUT(io_clk));
 GTP_IOCLKDIV #(.DIV_FACTOR("2")) div(.CLKIN(io_clk),.RST_N(locked),.CLKDIVOUT(half_raw));
 GTP_CLKBUFG half_buf(.CLKIN(half_raw),.CLKOUT(half_clk));
 reg [15:0] pattern; always @(posedge half_clk) pattern<=pattern+1'b1;
 wire [4:0] serial;
 genvar k;
 generate for(k=0;k<5;k=k+1) begin: pins
 wire [3:0] pair=k<4?{pattern[k+12],pattern[k+8],pattern[k+4],pattern[k]}:pattern[3:0];
 GTP_OSERDES #(.OSERDES_MODE("OSER4"),.WL_EXTEND("FALSE"),.GRS_EN("TRUE"),.LRS_EN("TRUE")) ser(.DO(serial[k]),.TQ(),.DI({4'd0,pair}),.TI(4'd0),.RCLK(half_clk),.SERCLK(io_clk),.OCLK(1'b0),.RST(!locked));
 if(k<4) GTP_OUTBUF pad(.I(serial[k]),.O(rgmii2_txd[k]));
 else GTP_OUTBUF pad(.I(serial[k]),.O(rgmii2_tx_ctl));
 end endgenerate
 GTP_OUTBUF clock_pad(.I(forward_clk),.O(rgmii2_txc));
endmodule
