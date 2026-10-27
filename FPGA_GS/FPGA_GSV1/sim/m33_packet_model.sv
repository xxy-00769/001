`timescale 1ns/1ps
module m3_byte_ram #(parameter BANKS=1,AW=11+$clog2(BANKS))(input wc,we,input [AW-1:0] wa,input [7:0] wd,input rc,input [AW-1:0] ra,output reg [7:0] rd);
 reg [7:0] mem[0:BANKS*2048-1];always @(posedge wc) if(we) mem[wa]<=wd;always @(posedge rc) rd<=mem[ra];
endmodule
