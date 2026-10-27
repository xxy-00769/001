module probe(input cmos1_pclk,input [7:0] cmos1_data,input cmos1_href,cmos1_vsync,output [9:0] q);
m34_input_capture #(.WIDTH(6)) lo(.clk(cmos1_pclk),.data({cmos1_href,cmos1_data[6:4],cmos1_data[1:0]}),.captured({q[8],q[6:4],q[1:0]}));
m34_input_capture #(.WIDTH(4)) hi(.clk(cmos1_pclk),.data({cmos1_vsync,cmos1_data[7],cmos1_data[3:2]}),.captured({q[9],q[7],q[3:2]}));
endmodule
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

