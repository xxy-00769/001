module probe(input cmos1_pclk,input d,output q);m34_input_capture #(.WIDTH(1)) u(.clk(cmos1_pclk),.data(d),.captured(q));endmodule
module m34_input_capture #(parameter WIDTH=10)(
 input clk,input [WIDTH-1:0] data,output [WIDTH-1:0] captured);
 wire ioclk /* synthesis syn_keep=1 */;
 GTP_IOCLKBUF #(.GATE_EN("FALSE")) local_clock /* synthesis syn_preserve=1 */ (.CLKIN(clk),.DI(1'b1),.CLKOUT(ioclk));
 genvar p;
 generate for(p=0;p<WIDTH;p=p+1) begin: pad
  wire [7:0] samples;wire din;
 GTP_INBUF input_buffer(.I(data[p]),.O(din));
  GTP_ISERDES #(.ISERDES_MODE("IMDDR"),.GRS_EN("FALSE"),.LRS_EN("FALSE")) sample(
   .DI(din),.ICLK(ioclk),.DESCLK(clk),.RCLK(clk),
   .WADDR(3'd0),.RADDR(3'd0),.RST(1'b0),.DO(samples));
  assign captured[p]=samples[6];
 end endgenerate
endmodule

