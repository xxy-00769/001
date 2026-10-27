`timescale 1ns/1ps
module hint_gain_tb;
 reg sc=0,pc=0,rst=0;always #10 sc=~sc;always #17 pc=~pc;
 reg [5:0] key=63;wire [5:0] pressed;wire [3:0] led,code,sc_code;wire ev,view,visible;
 m1_keys #(.DEBOUNCE_CYCLES(4)) keys(.clk(sc),.rst_n(rst),.key_n(key),.pressed(pressed),
 .intent_led(led),.view_request(view),.hint_event(ev),.hint_code(sc_code));
 m1_hint_cdc #(.HOLD_CYCLES(100)) hint(.sys_clk(sc),.pix_clk(pc),.rst_n(rst),.event_in(ev),.code_in(sc_code),.code(code),.visible(visible));
 integer events=0;always @(posedge sc) if(ev) events=events+1;
 reg [9:0] x=0;reg [8:0] y=0;wire area,pixel;
 m1_key_osd osd(.x(x),.y(y),.visible(visible),.code(code),.area(area),.pixel(pixel));
 reg [15:0] rgb=0;reg bypass=0;wire [23:0] adjusted,original;
 m1_display_gain gain(.rgb(rgb),.bypass(bypass),.adjusted(adjusted));
 m1_display_gain #(.ENABLE(0)) raw(.rgb(rgb),.bypass(1'b0),.adjusted(original));
 task press(input integer k,input integer expected);
  integer before_events,lit,xx,yy;
  begin
   before_events=events;@(negedge sc);key[k]=0;
   repeat(30) @(negedge sc);
   if(!visible || code!=expected || events!=before_events+1) $fatal(1,"key hint %0d code=%0d events=%0d",k+1,code,events);
   repeat(25) @(negedge sc);
   if(events!=before_events+1) $fatal(1,"Hold repeated");
   lit=0;
   for(yy=12;yy<28;yy=yy+1) for(xx=548;xx<788;xx=xx+1) begin
    x=xx;y=yy;#0.01;if(pixel) lit=lit+1;
   end
   if(lit==0) $fatal(1,"Empty hint glyph");
   x=547;#1;if(area) $fatal(1,"OSD bound");x=788;#1;if(area) $fatal(1,"OSD bound");
   @(negedge sc);key[k]=1;repeat(12) @(negedge sc);
  end
 endtask
 integer k,e,sum,r,g,b;reg [23:0] expected_rgb;
 function [7:0] bright(input integer c);begin bright=(c+c/4)>255 ? 255 : c+c/4;end endfunction
 initial begin
  #100;rst=1;repeat(10) @(negedge sc);
  if(visible) $fatal(1,"Reset hint visible");
  for(k=0;k<6;k=k+1) press(k,k+1);
  // New events restart the full timer, even while the previous hint is visible.
  if(hint.remaining<60) $fatal(1,"Hint not refreshed");
  repeat(110) @(negedge pc);if(visible) $fatal(1,"Hint did not expire");
  @(negedge sc);key[3]=0;repeat(30) @(negedge sc);
  for(k=0;k<3;k=k+1) begin press(k,9+k);if(led!=8) $fatal(1,"Stop priority LED");end
  key[3]=1;
  for(k=0;k<65536;k=k+1) begin
   rgb=k;bypass=0;#1;r={rgb[15:11],rgb[15:13]};g={rgb[10:5],rgb[10:9]};b={rgb[4:0],rgb[4:2]};
   expected_rgb={bright(r),bright(g),bright(b)};
   if(adjusted!==expected_rgb || original!=={r[7:0],g[7:0],b[7:0]}) $fatal(1,"Gain/saturation %h",rgb);
   bypass=1;#1;if(adjusted!==original) $fatal(1,"Bypass");
  end
  $display("HINT_GAIN_PASS six_keys=1 hold_no_repeat=1 refresh_timeout=1 denied_requests=3 glyphs=9 colors=65536 bypass=1 events=%0d",events);$finish;
 end
 initial begin #1000000;$fatal(1,"Timeout");end
endmodule
