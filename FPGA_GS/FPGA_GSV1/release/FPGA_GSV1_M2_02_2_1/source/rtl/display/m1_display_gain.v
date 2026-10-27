`timescale 1ns/1ps
// RGB565 expansion and conservative 1.25x gain, display branch only.
module m1_display_gain #(parameter ENABLE=1)(input [15:0] rgb,input bypass,output [23:0] adjusted);
 wire [7:0] r={rgb[15:11],rgb[15:13]},g={rgb[10:5],rgb[10:9]},b={rgb[4:0],rgb[4:2]};
 function [7:0] gain(input [7:0] c);
  reg [8:0] sum;
  begin sum={1'b0,c}+{3'b0,c[7:2]};gain=sum[8] ? 8'hff : sum[7:0];end
 endfunction
 assign adjusted=(!ENABLE || bypass) ? {r,g,b} : {gain(r),gain(g),gain(b)};
endmodule
