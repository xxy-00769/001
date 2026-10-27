`timescale 1ns/1ps
module m2_osd(input [9:0] x,input [8:0] y,input [1:0] view,
 input [2:0] mode,input hint_visible,input [3:0] hint_code,
 input [2:0] video_good,output reg area,output pixel);
 reg [5:0] text_id;reg [9:0] ox;reg [8:0] oy;reg [1:0] window_source;
 reg [5:0] hint_text;
 always @* begin
  case(hint_code)
   1,2,3,4:hint_text=20+hint_code;
   5:hint_text=25+view;
   6:hint_text=30+mode;
   9,10,11:hint_text=32+hint_code;
   default:hint_text=0;
  endcase
  area=0;text_id=0;ox=0;oy=0;
  window_source=view;
  if(view==3) begin
   if(y<240) window_source=x<400 ? 0 : 1;
   else window_source=x<400 ? 2 : 3;
  end
  if(y>=12 && y<28 && x>=12 && x<268) begin
   area=1;text_id=view+1;ox=12;oy=12;
  end else if(y>=32 && y<48 && x>=12 && x<268) begin
   area=1;text_id=10+mode;ox=12;oy=32;
  end else if(hint_visible && y>=12 && y<28 && x>=548 && x<788) begin
   area=1;text_id=hint_text;ox=548;oy=12;
  end else if(view==3 && y>=64 && y<80 && x>=88 && x<240) begin
   area=1;text_id=1;ox=88;oy=64;
  end else if(view==3 && y>=64 && y<80 && x>=408 && x<560) begin
   area=1;text_id=2;ox=408;oy=64;
  end else if(view==3 && y>=244 && y<260 && x>=88 && x<240) begin
   area=1;text_id=3;ox=88;oy=244;
  end else if(view==3 && y>=324 && y<340 && x>=448 && x<688) begin
   area=1;text_id=5;ox=448;oy=324;
  end else if(x>=80 && x<720 && y>=60 && y<420 && window_source<3 && !video_good[window_source]) begin
   ox=(view==3 && window_source==1) ? 408 : 88;
   oy=(view==3 && window_source==2) ? 300 : 140;
   if(y>=oy && y<oy+16 && x>=ox && x<ox+240) begin
    area=1;text_id=window_source==2 ? 6 : 7;
   end
  end
 end
 m2_text font(.text_id(text_id),.col(x-ox),.row(y-oy),.pixel(pixel));
endmodule
