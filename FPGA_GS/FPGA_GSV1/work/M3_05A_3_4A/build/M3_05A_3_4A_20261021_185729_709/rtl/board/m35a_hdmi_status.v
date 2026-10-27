`timescale 1ns/1ps
// Passive observation only. No output feeds video reset, qualification or DDR.
// All asynchronous observations are single-bit levels/toggles synchronized here.
module m35a_hdmi_status #(parameter MS_CYCLES=50000)(
 input clk,rst_n,configured,frame_toggle,format_ok,capture_ok,
 input published_toggle,has_frame,selected,display_fault,read_active,
 output reg [2:0] stage);
 reg [1:0] cfg,fr,fmt,cap,pub,ready,sel,fault,rd;
 reg fr_old,pub_old;
 reg [15:0] tick;
 reg [8:0] frame_age,publish_age,read_age;
 wire ms_tick=tick==MS_CYCLES-1;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   cfg<=0;fr<=0;fmt<=0;cap<=0;pub<=0;ready<=0;sel<=0;fault<=0;rd<=0;
   fr_old<=0;pub_old<=0;tick<=0;
   frame_age<=511;publish_age<=511;read_age<=511;stage<=0;
  end else begin
   cfg<={cfg[0],configured};fr<={fr[0],frame_toggle};
   fmt<={fmt[0],format_ok};cap<={cap[0],capture_ok};
   pub<={pub[0],published_toggle};ready<={ready[0],has_frame};
   sel<={sel[0],selected};fault<={fault[0],display_fault};
   rd<={rd[0],read_active};fr_old<=fr[1];pub_old<=pub[1];
   if(ms_tick) tick<=0;else tick<=tick+1'b1;
   if(fr[1]!=fr_old) frame_age<=0;
   else if(ms_tick && frame_age!=511) frame_age<=frame_age+1'b1;
   if(pub[1]!=pub_old) publish_age<=0;
   else if(ms_tick && publish_age!=511) publish_age<=publish_age+1'b1;
   if(rd[1]) read_age<=0;
   else if(ms_tick && read_age!=511) read_age<=read_age+1'b1;
   if(!cfg[1]) stage<=0;
   else if(frame_age>=50) stage<=1;
   else if(!fmt[1]) stage<=2;
   else if(!cap[1]) stage<=3;
   else if(!ready[1] || publish_age>=250) stage<=4;
   else if(!sel[1]) stage<=5;
   else if(fault[1] || read_age>=50) stage<=6;
   else stage<=7;
  end
 end
endmodule
