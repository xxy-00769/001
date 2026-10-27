module probe(input clk,output [3:0] data);
wire c;
GTP_CLKBUFG cb(.CLKIN(clk),.CLKOUT(c));
reg [7:0] counter=0;
always @(posedge c) counter<=counter+1'b1;
genvar i; generate for(i=0;i<4;i=i+1) begin: channel
 wire d,t;
 GTP_OSERDES #(.OSERDES_MODE("ODDR"),.WL_EXTEND("FALSE"),.GRS_EN("TRUE"),.LRS_EN("TRUE"),.TSDDR_INIT(1'b0)) od(
  .DO(d),.TQ(t),.DI({6'd0,counter[i*2+1],counter[i*2]}),.TI(4'd0),.RCLK(c),.SERCLK(c),.OCLK(1'b0),.RST(1'b0));
 GTP_OUTBUFT ob(.I(d),.T(t),.O(data[i]));
end endgenerate
endmodule

