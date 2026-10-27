`timescale 1ns/1ps
// MS7200 generic-board output is 24-bit parallel RGB888, positive 720p HS/VS.
// Accept 1650x750 totals and 1280x720 geometry (the latter checked by monitor).
module hdmi_input(input clk,ref_clk,rst_n,configured,vs,hs,de,
 input [7:0] r,g,b,output reg out_vs,out_de,output reg [15:0] rgb,
 output format_ok,output reg [31:0] received_frames,output input_beat);
 // Capture the rising-edge tuple with the local I/O clock, then use the
 // IOL memory register to hand it to the global clock. The pad sample edge
 // stays rising; the global clock insertion no longer moves that sample.
 wire pin_vs,pin_hs,pin_de;wire [15:0] pin_rgb;
 m34_input_capture #(.WIDTH(19)) pads(.clk(clk),
  .data({vs,hs,de,r[7:3],g[7:2],b[7:3]}),
  .captured({pin_vs,pin_hs,pin_de,pin_rgb}));
 reg [9:0] beat_count;
 always @(posedge clk or negedge rst_n)
  if(!rst_n) beat_count<=0;else beat_count<=beat_count+1'b1;
 assign input_beat=beat_count[9];
 reg vd,hd;reg [11:0] clocks,lines;reg bad_lines,geometry_ok;
 reg [1:0] cfg;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   vd<=0;hd<=0;clocks<=0;lines<=0;bad_lines<=1;geometry_ok<=0;
   cfg<=0;out_vs<=0;out_de<=0;rgb<=0;received_frames<=0;
  end else begin
   cfg<={cfg[0],configured};vd<=pin_vs;hd<=pin_hs;
   out_vs<=pin_vs;out_de<=pin_de && cfg[1];rgb<=pin_rgb;
   if(clocks!=4095) clocks<=clocks+1'b1;
   if(pin_hs && !hd) begin
    clocks<=0;if(lines!=4095) lines<=lines+1'b1;
    if(clocks!=1649) bad_lines<=1;
   end
   if(pin_vs && !vd) begin
    received_frames<=received_frames+1'b1;
    geometry_ok<=!bad_lines && lines==750 && cfg[1];
    lines<=(pin_hs && !hd) ? 12'd1 : 12'd0;bad_lines<=0;
   end
  end
 end
 // Check VS period using the independent 50-MHz reference; ±2% includes59.94.
 reg [2:0] vs_ref;reg [19:0] period;reg rate_ok;
 always @(posedge ref_clk or negedge rst_n) begin
  if(!rst_n) begin vs_ref<=0;period<=20'hfffff;rate_ok<=0;end
  else begin
   vs_ref<={vs_ref[1:0],pin_vs};
   if(period!=20'hfffff) period<=period+1'b1;
   if(vs_ref[1] && !vs_ref[2]) begin
    rate_ok<=period>=816666 && period<=850000;period<=0;
   end else if(period==20'hfffff) rate_ok<=0;
  end
 end
 assign format_ok=geometry_ok && rate_ok;
endmodule

// IMDDR's positive sample is stored on the following local falling edge,
// then transferred to the fabric on RCLK. A fixed memory address is enough
// because both clocks are the same input frequency, with bounded insertion
// skew checked by STA. Falling-edge data is not used. This is not an async
// FIFO and does not change the external sample edge.
module m34_input_capture #(parameter WIDTH=10)(
 input clk,input [WIDTH-1:0] data,output [WIDTH-1:0] captured);
 wire ioclk;
 GTP_IOCLKBUF #(.GATE_EN("FALSE")) local_clock(.CLKIN(clk),.DI(1'b1),.CLKOUT(ioclk));
 genvar p;
 generate for(p=0;p<WIDTH;p=p+1) begin: pad
  wire [7:0] samples;
  GTP_ISERDES #(.ISERDES_MODE("IMDDR"),.GRS_EN("FALSE"),.LRS_EN("FALSE")) sample(
   .DI(data[p]),.ICLK(ioclk),.DESCLK(clk),.RCLK(clk),
   .WADDR(3'd0),.RADDR(3'd0),.RST(1'b0),.DO(samples));
  assign captured[p]=samples[6];
 end endgenerate
endmodule

// First-failure indicator only. No video gating depends on this diagnostic.
module m34_hdmi_status #(parameter MS_CYCLES=50000)(
 input clk,rst_n,configured,input_beat,frame_toggle,format_ok,capture_ok,
 input published_toggle,has_frame,display_fault,output reg [2:0] stage);
 reg [1:0] cfg,hb,fr,fmt,pub,ready,fail;
 reg hb_old,fr_old,pub_old;
 reg [15:0] tick;
 reg [8:0] clock_age,frame_age,publish_age;
 wire ms_tick=tick==MS_CYCLES-1;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   cfg<=0;hb<=0;fr<=0;fmt<=0;pub<=0;ready<=0;fail<=0;
   hb_old<=0;fr_old<=0;pub_old<=0;tick<=0;
   clock_age<=511;frame_age<=511;publish_age<=511;stage<=0;
  end else begin
   cfg<={cfg[0],configured};hb<={hb[0],input_beat};fr<={fr[0],frame_toggle};
   fmt<={fmt[0],format_ok};pub<={pub[0],published_toggle};
   ready<={ready[0],has_frame};fail<={fail[0],display_fault};
   hb_old<=hb[1];fr_old<=fr[1];pub_old<=pub[1];
   if(ms_tick) tick<=0;else tick<=tick+1'b1;
   if(hb[1]!=hb_old) clock_age<=0;
   else if(ms_tick && clock_age!=511) clock_age<=clock_age+1'b1;
   if(fr[1]!=fr_old) frame_age<=0;
   else if(ms_tick && frame_age!=511) frame_age<=frame_age+1'b1;
   if(pub[1]!=pub_old) publish_age<=0;
   else if(ms_tick && publish_age!=511) publish_age<=publish_age+1'b1;
   if(!cfg[1]) stage<=0;
   else if(clock_age>=2) stage<=1;
   else if(frame_age>=50) stage<=2;
   else if(!fmt[1]) stage<=3;
   else if(!capture_ok) stage<=4;
   else if(!ready[1] || publish_age>=250) stage<=5;
   else if(fail[1]) stage<=6;
   else stage<=7;
  end
 end
endmodule
