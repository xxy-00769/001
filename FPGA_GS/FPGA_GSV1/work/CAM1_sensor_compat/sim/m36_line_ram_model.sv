`timescale 1ns/1ps
// Same one-clock packing contract as line_ram_model.sv; vector storage avoids
// eight independent array reads on every otherwise idle DDR clock.
module wr_fram_buf(input [31:0] wr_data,input [11:0] wr_addr,input wr_en,wr_clk,wr_rst,
 output reg [255:0] rd_data,input [8:0] rd_addr,input rd_clk,rd_rst);
 reg [255:0] memory[0:511];
 always @(posedge wr_clk) if(!wr_rst && wr_en) memory[wr_addr[11:3]][wr_addr[2:0]*32+:32]<=wr_data;
 always @(posedge rd_clk or posedge rd_rst) if(rd_rst) rd_data<=0;else rd_data<=memory[rd_addr];
endmodule
module rd_fram_buf(input [255:0] wr_data,input [8:0] wr_addr,input wr_en,wr_clk,wr_rst,
 output reg [31:0] rd_data,input [11:0] rd_addr,input rd_clk,rd_rst);
 reg [255:0] memory[0:511];
 always @(posedge wr_clk) if(!wr_rst && wr_en) memory[wr_addr]<=wr_data;
 always @(posedge rd_clk or posedge rd_rst) if(rd_rst) rd_data<=0;else rd_data<=memory[rd_addr[11:3]][rd_addr[2:0]*32+:32];
endmodule
