`timescale 1ns/1ps
// Two 1024x18 physical DRM primitives, 24 useful bits, one-clock read.
// Row1 uses same-port READ_BEFORE_WRITE. Row2 writes the previous column
// on A and independently reads the current column on B (never a collision).
module m2_filter_row #(parameter READ_FIRST=0)(
 input clk,rst_n,enable,input [9:0] address,
 input write_enable,input [9:0] write_address,input [23:0] write_data,
 output [23:0] read_data);
 genvar i;
 generate for(i=0;i<2;i=i+1) begin: slice
  wire [17:0] qa,qb;
  GTP_DRM18K #(.GRS_EN("FALSE"),.DATA_WIDTH_A(18),.DATA_WIDTH_B(18),
   .WRITE_MODE_A("READ_BEFORE_WRITE"),.DOA_REG(0),.DOB_REG(0),
   .RST_TYPE("ASYNC"),.RAM_MODE("TRUE_DUAL_PORT"),.SIM_DEVICE("LOGOS")) ram(
   .CLKA(clk),.CEA(READ_FIRST ? enable : write_enable),.WEA(write_enable),
   .ADDRA({write_address,2'b00,2'b11}),.ADDRA_HOLD(1'b0),
   .DIA({6'd0,write_data[i*12+:12]}),.CSA(3'd0),.DOA(qa),.ORCEA(1'b0),.RSTA(!rst_n),
   .CLKB(clk),.CEB(enable),.WEB(1'b0),.ADDRB({address,2'b00,2'b11}),.ADDRB_HOLD(1'b0),
   .DIB(18'd0),.CSB(3'd0),.DOB(qb),.ORCEB(1'b0),.RSTB(!rst_n),.WWCONF());
  assign read_data[i*12+:12]=READ_FIRST ? qa[11:0] : qb[11:0];
 end endgenerate
endmodule
