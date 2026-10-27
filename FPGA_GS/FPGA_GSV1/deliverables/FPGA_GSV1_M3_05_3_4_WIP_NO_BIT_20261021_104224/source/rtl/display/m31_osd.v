`timescale 1ns/1ps
module m31_osd(input clk,input [10:0] x,input [10:0] y,input [2:0] view,
 input [2:0] mode,input hint_visible,input [3:0] hint_code,
 input [2:0] hdmi_stage,
 input [3:0] video_good,input [2:0] feedback,output area,output pixel);
 reg area_raw;reg [5:0] text_id;reg [10:0] ox;reg [10:0] oy;reg [1:0] window_source;
 reg [5:0] hint_text;
 reg diagnostic;
 always @* begin
  case(hint_code)
   1,2,3,4:hint_text=20+hint_code;
   5:hint_text=view==4 ? 29 : 25+view;
   6:hint_text=30+mode;
   9,10,11:hint_text=32+hint_code;
   default:hint_text=0;
  endcase
  area_raw=0;text_id=0;ox=0;oy=0;diagnostic=0;
  window_source=view[1:0];
  if(view==4) begin
   if(y<540) window_source=x<960 ? 0 : 1;
   else window_source=x<960 ? 2 : 3;
  end
  if(y>=1052 && y<1068 && x>=12 && x<268) begin
   area_raw=1;text_id=48+feedback;ox=12;oy=1052;
  end else if(y>=12 && y<28 && x>=12 && x<268) begin
   area_raw=1;text_id=view==4 ? 4 : (view==3 ? 8 : view+1);ox=12;oy=12;
  end else if(y>=32 && y<48 && x>=12 && x<268) begin
   area_raw=1;text_id=10+mode;ox=12;oy=32;
  end else if(hint_visible && y>=12 && y<28 && x>=1668 && x<1908) begin
   area_raw=1;text_id=hint_text;ox=1668;oy=12;
  end else if(view==4 && y>=64 && y<80 && x>=12 && x<164) begin
   area_raw=1;text_id=1;ox=12;oy=64;
  end else if(view==4 && y>=64 && y<80 && x>=972 && x<1124) begin
   area_raw=1;text_id=2;ox=972;oy=64;
  end else if(view==4 && y>=552 && y<568 && x>=12 && x<164) begin
   area_raw=1;text_id=3;ox=12;oy=552;
  end else if(view==4 && y>=552 && y<568 && x>=972 && x<1212) begin
   area_raw=1;text_id=8;ox=972;oy=552;
  end else if(((view==4) || (x>=320 && x<1600 && y>=180 && y<900)) &&
      (!video_good[window_source] || (window_source==2 && hdmi_stage==6))) begin
   ox=(view==4 && window_source==1) ? 972 : (view==4 ? 12 : 332);
   oy=(view==4 && window_source>=2) ? 700 : (view==4 ? 160 : 340);
   if(view==4 && window_source==3) ox=972;
   if(y>=oy && y<oy+16 && x>=ox && x<ox+240) begin
    area_raw=1;text_id=window_source==3 ? 9 : 7;
    if(window_source==2) begin
     // L0..L7 identify the first failing stage; no resolution advice.
     text_id=0;diagnostic=1;area_raw=x<ox+32;
    end
   end
  end
 end
 // Decode -> registered text/coordinates -> registered glyph -> ROM bits.
 reg [5:0] text_d;reg [7:0] col_d;reg [3:0] row_d;reg [1:0] area_d;reg diagnostic_d;
 always @(posedge clk) begin
  text_d<=text_id;col_d<=x-ox;row_d<=y-oy;area_d<={area_d[0],area_raw};diagnostic_d<=diagnostic;
 end
 assign area=area_d[1];
 wire font_pixel;
 m31_text font(.clk(clk),.text_id(text_d),.col(col_d),.row(row_d),.pixel(font_pixel));
 function [14:0] digit(input [2:0] n);
  begin case(n)
   0:digit=15'b111_101_101_101_111;
   1:digit=15'b010_110_010_010_111;
   2:digit=15'b111_001_111_100_111;
   3:digit=15'b111_001_111_001_111;
   4:digit=15'b101_101_111_001_001;
   5:digit=15'b111_100_111_001_111;
   6:digit=15'b111_100_111_101_111;
   7:digit=15'b111_001_001_001_001;
  endcase end
 endfunction
 wire [14:0] shape=digit(hdmi_stage);
 reg diag_pixel;reg [2:0] digit_row;
 always @* begin
  case(row_d[3:1])
   0:digit_row=shape[14:12];1:digit_row=shape[11:9];
   2:digit_row=shape[8:6];3:digit_row=shape[5:3];
   default:digit_row=shape[2:0];
  endcase
  diag_pixel=0;
  if(diagnostic_d && row_d<10) begin
   if(col_d<6) diag_pixel=col_d<2 || row_d>=8;
   else case(col_d)
    10,11:diag_pixel=digit_row[2];
    12,13:diag_pixel=digit_row[1];
    14,15:diag_pixel=digit_row[0];
   endcase
  end
 end
 reg diag_delay;
 always @(posedge clk) diag_delay<=diag_pixel;
 assign pixel=font_pixel | diag_delay;
endmodule
