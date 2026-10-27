`timescale 1ns/1ps
module m2_filter_row #(parameter READ_FIRST=0)(input clk,rst_n,enable,input [9:0] address,
 input write_enable,input [9:0] write_address,input [23:0] write_data,output reg [23:0] read_data);
 reg [23:0] memory[0:1023];
 always @(posedge clk or negedge rst_n)
  if(!rst_n) read_data<=0;
  else begin
   if(enable) read_data<=memory[READ_FIRST?write_address:address];
   if(write_enable) memory[write_address]<=write_data;
  end
endmodule
