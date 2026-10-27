`timescale 1ns/1ps
module m31_osd(input [10:0] x,input [10:0] y,input [2:0] view,
 input [2:0] mode,input hint_visible,input [3:0] hint_code,
 input [3:0] video_good,input [2:0] feedback,output reg area,output pixel);
 reg [5:0] text_id;reg [10:0] ox;reg [10:0] oy;reg [1:0] window_source;
 reg [5:0] hint_text;
 always @* begin
  case(hint_code)
   1,2,3,4:hint_text=20+hint_code;
   5:hint_text=view==4 ? 29 : 25+view;
   6:hint_text=30+mode;
   9,10,11:hint_text=32+hint_code;
   default:hint_text=0;
  endcase
  area=0;text_id=0;ox=0;oy=0;
  window_source=view[1:0];
  if(view==4) begin
   if(y<540) window_source=x<960 ? 0 : 1;
   else window_source=x<960 ? 2 : 3;
  end
  if(y>=1052 && y<1068 && x>=12 && x<268) begin
   area=1;text_id=48+feedback;ox=12;oy=1052;
  end else if(y>=12 && y<28 && x>=12 && x<268) begin
   area=1;text_id=view==4 ? 4 : (view==3 ? 8 : view+1);ox=12;oy=12;
  end else if(y>=32 && y<48 && x>=12 && x<268) begin
   area=1;text_id=10+mode;ox=12;oy=32;
  end else if(hint_visible && y>=12 && y<28 && x>=1668 && x<1908) begin
   area=1;text_id=hint_text;ox=1668;oy=12;
  end else if(view==4 && y>=64 && y<80 && x>=12 && x<164) begin
   area=1;text_id=1;ox=12;oy=64;
  end else if(view==4 && y>=64 && y<80 && x>=972 && x<1124) begin
   area=1;text_id=2;ox=972;oy=64;
  end else if(view==4 && y>=552 && y<568 && x>=12 && x<164) begin
   area=1;text_id=3;ox=12;oy=552;
  end else if(view==4 && y>=552 && y<568 && x>=972 && x<1212) begin
   area=1;text_id=8;ox=972;oy=552;
  end else if(((view==4) || (x>=320 && x<1600 && y>=180 && y<900)) && !video_good[window_source]) begin
   ox=(view==4 && window_source==1) ? 972 : (view==4 ? 12 : 332);
   oy=(view==4 && window_source>=2) ? 700 : (view==4 ? 160 : 340);
   if(view==4 && window_source==3) ox=972;
   if(y>=oy && y<oy+16 && x>=ox && x<ox+240) begin
    area=1;text_id=window_source==3 ? 9 : (window_source==2 ? 6 : 7);
   end
  end
 end
 m3_text font(.text_id(text_id),.col(x-ox),.row(y-oy),.pixel(pixel));
endmodule
