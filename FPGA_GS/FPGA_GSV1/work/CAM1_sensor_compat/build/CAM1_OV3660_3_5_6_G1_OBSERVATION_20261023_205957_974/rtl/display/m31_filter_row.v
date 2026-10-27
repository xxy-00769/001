`timescale 1ns/1ps
// Three 2048x9 physical DRM primitives, 24 useful bits, one-clock read.
// Row1 uses same-port READ_BEFORE_WRITE. Row2 writes the previous column
// on A and independently reads the current column on B (never a collision).
module m31_filter_row #(parameter READ_FIRST=0)(
 input clk,rst_n,enable,input [10:0] address,
 input write_enable,input [10:0] write_address,input [23:0] write_data,
 output [23:0] read_data);
 genvar i;
 generate for(i=0;i<3;i=i+1) begin: slice
  wire [8:0] qa,qb;
  GTP_DRM18K #(.GRS_EN("FALSE"),.DATA_WIDTH_A(9),.DATA_WIDTH_B(9),
   .WRITE_MODE_A("READ_BEFORE_WRITE"),.DOA_REG(0),.DOB_REG(0),
   .RST_TYPE("ASYNC"),.RAM_MODE("TRUE_DUAL_PORT"),.SIM_DEVICE("LOGOS")) ram(
   .CLKA(clk),.CEA(READ_FIRST ? enable : write_enable),.WEA(write_enable),
   .ADDRA({write_address,1'b0,2'b11}),.ADDRA_HOLD(1'b0),
   .DIA({1'b0,write_data[i*8+:8]}),.CSA(3'd0),.DOA(qa),.ORCEA(1'b0),.RSTA(!rst_n),
   .CLKB(clk),.CEB(enable),.WEB(1'b0),.ADDRB({address,1'b0,2'b11}),.ADDRB_HOLD(1'b0),
   .DIB(9'd0),.CSB(3'd0),.DOB(qb),.ORCEB(1'b0),.RSTB(!rst_n),.WWCONF());
  assign read_data[i*8+:8]=READ_FIRST ? qa[7:0] : qb[7:0];
 end endgenerate
endmodule
