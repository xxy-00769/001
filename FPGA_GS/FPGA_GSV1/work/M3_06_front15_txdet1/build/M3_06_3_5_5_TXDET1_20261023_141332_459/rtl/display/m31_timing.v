`timescale 1ns/1ps
// CEA 1080p: 2200x1125, +HS/+VS. 148.5MHz =60Hz; 74.25MHz =30Hz.
// Read RAM and its half-word select have two pixel cycles of latency.
module m31_timing(input clk,rst_n,quad,
 output frame_sync,read_request,hs,vs,de,image_area,
 output [10:0] raw_x,raw_y,active_x,active_y);
 reg [11:0] h;reg [10:0] v;
 wire active=h>=192 && h<2112 && v>=41 && v<1121;
 assign raw_x=h-12'd192;assign raw_y=v-11'd41;
 wire image=active && (quad || (raw_x>=320 && raw_x<1600 && raw_y>=180 && raw_y<900));
 reg [1:0] hd,vd,dd,id;reg [10:0] x1,x2,y1,y2;
 assign frame_sync=rst_n && v<5;
 assign read_request=rst_n && image;
 assign hs=hd[1];assign vs=vd[1];assign de=dd[1];assign image_area=id[1];
 assign active_x=x2;assign active_y=y2;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin h<=0;v<=0;hd<=0;vd<=0;dd<=0;id<=0;x1<=0;x2<=0;y1<=0;y2<=0;end
  else begin
   if(h==2199) begin h<=0;v<=v==1124 ? 0 : v+1'b1;end else h<=h+1'b1;
   hd<={hd[0],h<44};vd<={vd[0],v<5};dd<={dd[0],active};id<={id[0],image};
   x1<=raw_x;x2<=x1;y1<=raw_y;y2<=y1;
  end
 end
endmodule
