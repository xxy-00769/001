`timescale 1ns/1ps
// Fast transaction-equivalent model for long 720-row runs. Actual generated
// RAM + GTP primitives are separately exercised by smoke/joint/reader cases.
// Same 4096x32 capacity, 256-bit packing, synchronous one-clock read latency.
module wr_fram_buf(input [31:0] wr_data,input [11:0] wr_addr,input wr_en,wr_clk,wr_rst,
 output reg [255:0] rd_data,input [8:0] rd_addr,input rd_clk,rd_rst);
 reg [31:0] memory[0:4095];integer i;
 always @(posedge wr_clk) if(!wr_rst && wr_en) memory[wr_addr]<=wr_data;
 always @(posedge rd_clk or posedge rd_rst)
  if(rd_rst) rd_data<=0;
  else for(i=0;i<8;i=i+1) rd_data[i*32+:32]<=memory[rd_addr*8+i];
endmodule
module rd_fram_buf(input [255:0] wr_data,input [8:0] wr_addr,input wr_en,wr_clk,wr_rst,
 output reg [31:0] rd_data,input [11:0] rd_addr,input rd_clk,rd_rst);
 reg [31:0] memory[0:4095];integer i;
 always @(posedge wr_clk) if(!wr_rst && wr_en)
  for(i=0;i<8;i=i+1) memory[wr_addr*8+i]<=wr_data[i*32+:32];
 always @(posedge rd_clk or posedge rd_rst)
  if(rd_rst) rd_data<=0;else rd_data<=memory[rd_addr];
endmodule
