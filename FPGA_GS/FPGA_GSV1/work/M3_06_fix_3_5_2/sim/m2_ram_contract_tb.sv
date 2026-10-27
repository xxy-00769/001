`timescale 1ns/1ps
module m2_ram_contract_tb;
 reg wc=0,rc=0,reset=1;always #5 wc=~wc;always #16.923077 rc=~rc;
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 reg we=0;reg [8:0] wa=0;reg [255:0] wd=0;reg [11:0] ra=0;wire [31:0] rd;
 rd_fram_buf reader(.wr_clk(wc),.wr_rst(reset),.wr_en(we),.wr_addr(wa),.wr_data(wd),
  .rd_clk(rc),.rd_rst(reset),.rd_addr(ra),.rd_data(rd));
 reg wwe=0;reg [11:0] wwa=0;reg [31:0] wwd=0;reg [8:0] wra=0;wire [255:0] wrd;
 wr_fram_buf writer(.wr_clk(wc),.wr_rst(reset),.wr_en(wwe),.wr_addr(wwa),.wr_data(wwd),
  .rd_clk(rc),.rd_rst(reset),.rd_addr(wra),.rd_data(wrd));
 function [31:0] pattern(input integer epoch,a);pattern=(32'h9e3779b9*a)^32'hc57a6d2f^(epoch*32'h10204081);endfunction
 integer pass,a,l,checks=0;
 initial begin
  #100;@(negedge wc);reset=0;
  for(pass=0;pass<3;pass++) begin
   @(negedge wc);
   for(a=0;a<512;a++) begin
    we=1;wa=a;for(l=0;l<8;l++) wd[l*32+:32]=pattern(pass,a*8+l);
    @(negedge wc);we=0;if(a%5==3) repeat(2) @(negedge wc);
   end
   for(a=0;a<4096;a++) begin
    @(negedge rc);ra=a;@(posedge rc);#1;
    if(rd!==pattern(pass,a)) $fatal(1,"read RAM packing/latency wrap=%0d addr=%0d got=%h",pass,a,rd);checks++;
   end
   for(a=0;a<4096;a++) begin
    @(negedge wc);wwe=1;wwa=a;wwd=pattern(pass,a);
   end
   @(negedge wc);wwe=0;
   for(a=0;a<512;a++) begin
    @(negedge rc);wra=a;@(posedge rc);#1;
    for(l=0;l<8;l++) begin
     if(wrd[l*32+:32]!==pattern(pass,a*8+l)) $fatal(1,"write RAM packing/latency wrap=%0d addr=%0d lane=%0d",pass,a,l);checks++;
    end
   end
  end
  $display("M2_RAM_CONTRACT_PASS checks=%0d wraps=3 generated_read_and_write=1 read_latency=1",checks);$finish;
 end
endmodule
