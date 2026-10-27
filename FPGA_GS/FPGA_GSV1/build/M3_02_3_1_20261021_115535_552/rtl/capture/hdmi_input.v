`timescale 1ns/1ps
// MS7200 generic-board output is 24-bit parallel RGB888, positive 720p HS/VS.
// Accept 1650x750 totals and 1280x720 geometry (the latter checked by monitor).
module hdmi_input(input clk,ref_clk,rst_n,configured,vs,hs,de,
 input [7:0] r,g,b,output reg out_vs,out_de,output reg [15:0] rgb,
 output format_ok,output reg [31:0] received_frames);
 reg vd,hd;reg [11:0] clocks,lines;reg bad_lines,geometry_ok;
 reg [1:0] cfg;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   vd<=0;hd<=0;clocks<=0;lines<=0;bad_lines<=1;geometry_ok<=0;
   cfg<=0;out_vs<=0;out_de<=0;rgb<=0;received_frames<=0;
  end else begin
   cfg<={cfg[0],configured};vd<=vs;hd<=hs;
   out_vs<=vs;out_de<=de && cfg[1];rgb<={r[7:3],g[7:2],b[7:3]};
   if(clocks!=4095) clocks<=clocks+1'b1;
   if(hs && !hd) begin
    clocks<=0;if(lines!=4095) lines<=lines+1'b1;
    if(clocks!=1649) bad_lines<=1;
   end
   if(vs && !vd) begin
    received_frames<=received_frames+1'b1;
    geometry_ok<=!bad_lines && lines==750 && cfg[1];
    lines<=(hs && !hd) ? 12'd1 : 12'd0;bad_lines<=0;
   end
  end
 end
 // Check VS period using the independent 50-MHz reference; ±2% includes59.94.
 reg [2:0] vs_ref;reg [19:0] period;reg rate_ok;
 always @(posedge ref_clk or negedge rst_n) begin
  if(!rst_n) begin vs_ref<=0;period<=20'hfffff;rate_ok<=0;end
  else begin
   vs_ref<={vs_ref[1:0],vs};
   if(period!=20'hfffff) period<=period+1'b1;
   if(vs_ref[1] && !vs_ref[2]) begin
    rate_ok<=period>=816666 && period<=850000;period<=0;
   end else if(period==20'hfffff) rate_ok<=0;
  end
 end
 assign format_ok=geometry_ok && rate_ok;
endmodule
