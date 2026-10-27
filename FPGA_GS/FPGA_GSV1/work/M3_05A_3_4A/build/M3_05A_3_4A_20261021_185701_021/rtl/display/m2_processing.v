`timescale 1ns/1ps
// Display-only RGB processing. Four registered stages, all raster metadata
// follows the same path. Mean uses a causal 3x3 aperture, anchored bottom-right;
// the first two rows/columns of EACH window use the original pixel.
module m2_processing #(parameter THRESHOLD=128)(
 input clk,rst_n,input [23:0] rgb,input hs,vs,de,image,
 input [9:0] x,input [8:0] y,input quad,input [2:0] mode,
 output reg [23:0] out_rgb,output out_hs,out_vs,out_de,out_image,
 output [9:0] out_x,output [8:0] out_y);
 wire [7:0] r=rgb[23:16],g=rgb[15:8],b=rgb[7:0];
 wire [15:0] luma=77*r+150*g+29*b+16'd128;
 wire signed [18:0] cb_calc=19'sd32896-19'sd43*$signed({1'b0,r})-
                           19'sd85*$signed({1'b0,g})+19'sd128*$signed({1'b0,b});
 wire signed [18:0] cr_calc=19'sd32896+19'sd128*$signed({1'b0,r})-
                           19'sd107*$signed({1'b0,g})-19'sd21*$signed({1'b0,b});
 function [7:0] chroma;input signed [18:0] n;
  begin if(n<0) chroma=0;else if(n>65535) chroma=255;else chroma=n[15:8];end
 endfunction
 reg [23:0] c[0:2];reg [7:0] lum[0:2],cb[0:2],cr[0:2];
 reg [9:0] px[0:3];reg [8:0] py[0:3];
 reg [2:0] md[0:2];reg [3:0] hs_d,vs_d,de_d,im_d,q_d;
 wire [9:0] lx=px[1]-10'd80;
 wire [8:0] ly=py[1]-9'd60;
 wire [9:0] local_x=q_d[1] && lx>=320 ? lx-320 : lx;
 wire [8:0] local_y=q_d[1] && ly>=180 ? ly-180 : ly;
 reg border;
 // Global columns distinguish left/right windows; local_y validity prevents
 // reading a preceding source at the top/bottom seam without clearing RAM.
 wire [23:0] above1,above2;
 reg [9:0] prev_r1,prev_r2,prev_g1,prev_g2,prev_b1,prev_b2;
 wire [9:0] vr={2'b0,c[1][23:16]}+above1[23:16]+above2[23:16];
 wire [9:0] vg={2'b0,c[1][15:8]}+above1[15:8]+above2[15:8];
 wire [9:0] vb={2'b0,c[1][7:0]}+above1[7:0]+above2[7:0];
 reg [11:0] sum_r,sum_g,sum_b;
 wire [27:0] mean_r=sum_r*16'd7282,mean_g=sum_g*16'd7282,mean_b=sum_b*16'd7282;
 wire [9:0] ox=px[2]-10'd80;
 wire [9:0] wx=q_d[2] && ox>=320 ? ox-320 : ox;
 wire [9:0] width=q_d[2] ? 320 : 640;
 wire [7:0] component=wx<width/3 ? lum[2] : (wx<(width*2)/3 ? cb[2] : cr[2]);
 integer i;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   hs_d<=0;vs_d<=0;de_d<=0;im_d<=0;q_d<=0;out_rgb<=0;
   prev_r1<=0;prev_r2<=0;prev_g1<=0;prev_g2<=0;prev_b1<=0;prev_b2<=0;
   sum_r<=0;sum_g<=0;sum_b<=0;border<=1;
   for(i=0;i<4;i=i+1) begin px[i]<=0;py[i]<=0;end
   for(i=0;i<3;i=i+1) begin c[i]<=0;lum[i]<=0;cb[i]<=0;cr[i]<=0;md[i]<=0;end
  end else begin
   hs_d<={hs_d[2:0],hs};vs_d<={vs_d[2:0],vs};de_d<={de_d[2:0],de};
   im_d<={im_d[2:0],image};q_d<={q_d[2:0],quad};
   px[0]<=x;py[0]<=y;c[0]<=rgb;lum[0]<=luma[15:8];cb[0]<=chroma(cb_calc);cr[0]<=chroma(cr_calc);md[0]<=mode;
   for(i=1;i<4;i=i+1) begin px[i]<=px[i-1];py[i]<=py[i-1];end
   for(i=1;i<3;i=i+1) begin c[i]<=c[i-1];lum[i]<=lum[i-1];cb[i]<=cb[i-1];cr[i]<=cr[i-1];md[i]<=md[i-1];end
   if(im_d[1]) begin
    prev_r1<=vr;prev_g1<=vg;prev_b1<=vb;
    prev_r2<=prev_r1;prev_g2<=prev_g1;prev_b2<=prev_b1;
    sum_r<={2'b0,vr}+prev_r1+prev_r2;
    sum_g<={2'b0,vg}+prev_g1+prev_g2;
    sum_b<={2'b0,vb}+prev_b1+prev_b2;
   end
   border<=local_x<2 || local_y<2;
   case(md[2])
    1:out_rgb<={3{lum[2]}};
    2:out_rgb<=border ? c[2] : {mean_r[23:16],mean_g[23:16],mean_b[23:16]};
    3:out_rgb<=lum[2]>=THRESHOLD ? 24'hffffff : 0;
    4:out_rgb<={3{component}};
    default:out_rgb<=c[2];
   endcase
  end
 end
 // Physical DRM with the original one-clock read latency.
 wire [9:0] address=px[0]-10'd80;
 wire row_enable=im_d[0] && address<640;
 reg row_enable_d; reg [9:0] row_address_d;
 always @(posedge clk or negedge rst_n)
  if(!rst_n) begin row_enable_d<=0;row_address_d<=0;end
  else begin row_enable_d<=row_enable;row_address_d<=address;end
 m2_filter_row #(.READ_FIRST(1)) row1(.clk(clk),.rst_n(rst_n),
  .enable(row_enable),.address(address),.write_enable(row_enable),
  .write_address(address),.write_data(c[0]),.read_data(above1));
 m2_filter_row row2(.clk(clk),.rst_n(rst_n),
  .enable(row_enable),.address(address),.write_enable(row_enable_d),
  .write_address(row_address_d),.write_data(above1),.read_data(above2));
 assign out_hs=hs_d[3];assign out_vs=vs_d[3];assign out_de=de_d[3];assign out_image=im_d[3];
 assign out_x=px[3];assign out_y=py[3];
endmodule
