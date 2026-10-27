module probe(input cmos1_pclk,input [7:0] cmos1_data,input cmos1_href,cmos1_vsync,output [9:0] q);
m34_input_capture #(.WIDTH(6)) lo(.clk(cmos1_pclk),.data({cmos1_href,cmos1_data[6:4],cmos1_data[1:0]}),.captured({q[8],q[6:4],q[1:0]}));
m34_input_capture #(.WIDTH(4)) hi(.clk(cmos1_pclk),.data({cmos1_vsync,cmos1_data[7],cmos1_data[3:2]}),.captured({q[9],q[7],q[3:2]}));
endmodule
module m34_input_capture #(parameter WIDTH=10)(input clk,input [WIDTH-1:0] data,output reg [WIDTH-1:0] captured);
wire local_clk /* synthesis syn_keep=1 */;
GTP_CLKBUFR region_clock /* synthesis syn_preserve=1 */ (.CLKIN(clk),.CLKOUT(local_clk));
wire global_clk;GTP_CLKBUFG global_clock(.CLKIN(clk),.CLKOUT(global_clk));
reg [WIDTH-1:0] sample /* synthesis syn_useioff=0 */;
reg [WIDTH-1:0] handoff;
always @(posedge local_clk) sample<=data;
always @(negedge local_clk) handoff<=sample;
always @(posedge global_clk) captured<=handoff;
endmodule
