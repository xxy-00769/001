`timescale 1ns/1ps
module output_tb;
reg pix_clk=0; always #5 pix_clk=~pix_clk;
reg panel_image=0,show_capture_video=0,de_o=0;
reg panel_hs=0,panel_vs=0,panel_de=0;
reg [15:0] o_rgb565=0;
reg [7:0] r_out,g_out,b_out;
reg vs_out,hs_out,de_out;
     function [7:0] display_brighten;
        input [7:0] value;
        reg [8:0] boosted;
        begin
           boosted = {1'b0,value} + {4'b0,value[7:3]};
           display_brighten = boosted[8] ? 8'hff : boosted[7:0];
        end
     endfunction
     always @(posedge pix_clk) begin
        r_out <= (panel_image && show_capture_video && de_o) ? display_brighten({o_rgb565[15:11],o_rgb565[15:13]}) : 8'h00;
        g_out <= (panel_image && show_capture_video && de_o) ? display_brighten({o_rgb565[10:5],o_rgb565[10:9]}) : 8'h00;
        b_out <= (panel_image && show_capture_video && de_o) ? display_brighten({o_rgb565[4:0],o_rgb565[4:2]}) : 8'h00;
        vs_out <= panel_vs;
        hs_out <= panel_hs;
        de_out <= panel_de;
     end

integer i,k,r,g,b; integer er,eg,eb;
initial begin
for(k=0;k<8;k=k+1) begin
 for(i=0;i<65536;i=i+1) begin
  @(negedge pix_clk);
  {panel_image,show_capture_video,de_o}=k;
  o_rgb565=i; {panel_hs,panel_vs,panel_de}=i%8;
  r=((i>>11)&31)*255/31;
  g=((i>>5)&63)*255/63;
  b=(i&31)*255/31;
  // Bit replication reference, then uniform 9/8 saturation.
  r=(((i>>11)&31)<<3)|((i>>13)&7);
  g=(((i>>5)&63)<<2)|((i>>9)&3);
  b=((i&31)<<3)|((i>>2)&7);
  er=r+r/8; if(er>255) er=255;
  eg=g+g/8; if(eg>255) eg=255;
  eb=b+b/8; if(eb>255) eb=255;
  if(k!=7) begin er=0;eg=0;eb=0;end
  @(posedge pix_clk); #1;
  if(r_out!==er || g_out!==eg || b_out!==eb) $fatal(1,"RGB mismatch k=%0d rgb565=%h",k,o_rgb565);
  if({hs_out,vs_out,de_out}!=={panel_hs,panel_vs,panel_de}) $fatal(1,"Sync alignment changed");
 end
end
$display("OUTPUT_PASS rgb565_values=65536 gating_combinations=8 black_margins=1 gain=9/8 saturation=1 sync_latency_preserved=1");
$finish;
end
endmodule
