`timescale 1ns/1ps
// Five matched stages. Color products / partial sums / clamp / align / select.
// Mean: row RAM / row alignment / vertical sum / horizontal sum / multiply.
module m31_processing #(parameter THRESHOLD=128)(
 input clk,rst_n,input [23:0] rgb,input hs,vs,de,image,
 input [10:0] x,input [10:0] y,input quad,input [2:0] mode,
 output reg [23:0] out_rgb,output out_hs,out_vs,out_de,out_image,
 output [10:0] out_x,output [10:0] out_y);
 wire [7:0] r=rgb[23:16],g=rgb[15:8],b=rgb[7:0];
 reg [15:0] yr,yg,yb,cbr,cbg,cbb,crr,crg,crb;
 reg [15:0] y_sum;reg signed [18:0] cb_rg,cr_rg;
 reg [15:0] cbb_d,crb_d;
 reg [7:0] lum2,cb2,cr2,lum3,cb3,cr3;
 function [7:0] chroma;input signed [18:0] n;
  begin if(n<0) chroma=0;else if(n>65535) chroma=255;else chroma=n[15:8];end
 endfunction
 reg [23:0] c[0:3];reg [2:0] md[0:3];
 reg [10:0] px[0:4],py[0:4];reg [4:0] hs_d,vs_d,de_d,im_d,q_d;
 wire [10:0] lx=px[2]-(q_d[2] ? 11'd0 : 11'd320);
 wire [10:0] ly=py[2]-(q_d[2] ? 11'd0 : 11'd180);
 wire [10:0] local_x=q_d[2] && lx>=960 ? lx-960 : lx;
 wire [10:0] local_y=q_d[2] && ly>=540 ? ly-540 : ly;
 reg border;
 wire [23:0] above1,above2;
 reg [9:0] vertical_r,vertical_g,vertical_b;
 reg [9:0] prev_r1,prev_r2,prev_g1,prev_g2,prev_b1,prev_b2;
 reg [11:0] sum_r,sum_g,sum_b;
 wire [27:0] mean_r=sum_r*16'd7282,mean_g=sum_g*16'd7282,mean_b=sum_b*16'd7282;
 wire [10:0] ox=px[3]-(q_d[3] ? 11'd0 : 11'd320);
 wire [10:0] wx=q_d[3] && ox>=960 ? ox-960 : ox;
 wire [7:0] component=wx<(q_d[3] ? 11'd320 : 11'd426) ? lum3 :
                           (wx<(q_d[3] ? 11'd640 : 11'd853) ? cb3 : cr3);
 integer i;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   hs_d<=0;vs_d<=0;de_d<=0;im_d<=0;q_d<=0;out_rgb<=0;
   yr<=0;yg<=0;yb<=0;cbr<=0;cbg<=0;cbb<=0;crr<=0;crg<=0;crb<=0;
   y_sum<=0;cb_rg<=0;cr_rg<=0;cbb_d<=0;crb_d<=0;
   lum2<=0;cb2<=0;cr2<=0;lum3<=0;cb3<=0;cr3<=0;
   vertical_r<=0;vertical_g<=0;vertical_b<=0;
   prev_r1<=0;prev_r2<=0;prev_g1<=0;prev_g2<=0;prev_b1<=0;prev_b2<=0;
   sum_r<=0;sum_g<=0;sum_b<=0;border<=1;
   for(i=0;i<5;i=i+1) begin px[i]<=0;py[i]<=0;end
   for(i=0;i<4;i=i+1) begin c[i]<=0;md[i]<=0;end
  end else begin
   hs_d<={hs_d[3:0],hs};vs_d<={vs_d[3:0],vs};de_d<={de_d[3:0],de};
   im_d<={im_d[3:0],image};q_d<={q_d[3:0],quad};
   px[0]<=x;py[0]<=y;c[0]<=rgb;md[0]<=mode;
   for(i=1;i<5;i=i+1) begin px[i]<=px[i-1];py[i]<=py[i-1];end
   for(i=1;i<4;i=i+1) begin c[i]<=c[i-1];md[i]<=md[i-1];end
   yr<=77*r;yg<=150*g;yb<=29*b;
   cbr<=43*r;cbg<=85*g;cbb<=128*b;crr<=128*r;crg<=107*g;crb<=21*b;
   y_sum<=yr+yg+yb+16'd128;
   cb_rg<=19'sd32896-$signed({3'b0,cbr})-$signed({3'b0,cbg});
   cr_rg<=19'sd32896+$signed({3'b0,crr})-$signed({3'b0,crg});
   cbb_d<=cbb;crb_d<=crb;
   lum2<=y_sum[15:8];cb2<=chroma(cb_rg+$signed({3'b0,cbb_d}));cr2<=chroma(cr_rg-$signed({3'b0,crb_d}));
   lum3<=lum2;cb3<=cb2;cr3<=cr2;
   vertical_r<={2'b0,c[1][23:16]}+above1[23:16]+above2[23:16];
   vertical_g<={2'b0,c[1][15:8]}+above1[15:8]+above2[15:8];
   vertical_b<={2'b0,c[1][7:0]}+above1[7:0]+above2[7:0];
   if(im_d[2]) begin
    prev_r1<=vertical_r;prev_g1<=vertical_g;prev_b1<=vertical_b;
    prev_r2<=prev_r1;prev_g2<=prev_g1;prev_b2<=prev_b1;
    sum_r<={2'b0,vertical_r}+prev_r1+prev_r2;
    sum_g<={2'b0,vertical_g}+prev_g1+prev_g2;
    sum_b<={2'b0,vertical_b}+prev_b1+prev_b2;
   end
   border<=local_x<2 || local_y<2;
   case(md[3])
    1:out_rgb<={3{lum3}};
    2:out_rgb<=border ? c[3] : {mean_r[23:16],mean_g[23:16],mean_b[23:16]};
    3:out_rgb<=lum3>=THRESHOLD ? 24'hffffff : 0;
    4:out_rgb<={3{component}};
    default:out_rgb<=c[3];
   endcase
  end
 end
 wire [10:0] address=px[0]-(q_d[0] ? 11'd0 : 11'd320);
 wire row_enable=im_d[0] && address<(q_d[0] ? 1920 : 1280);
 reg row_enable_d;reg [10:0] row_address_d;
 always @(posedge clk or negedge rst_n)
  if(!rst_n) begin row_enable_d<=0;row_address_d<=0;end
  else begin row_enable_d<=row_enable;row_address_d<=address;end
 m31_filter_row #(.READ_FIRST(1)) row1(.clk(clk),.rst_n(rst_n),
  .enable(row_enable),.address(address),.write_enable(row_enable),
  .write_address(address),.write_data(c[0]),.read_data(above1));
 m31_filter_row row2(.clk(clk),.rst_n(rst_n),
  .enable(row_enable),.address(address),.write_enable(row_enable_d),
  .write_address(row_address_d),.write_data(above1),.read_data(above2));
 assign out_hs=hs_d[4];assign out_vs=vs_d[4];assign out_de=de_d[4];assign out_image=im_d[4];
 assign out_x=px[4];assign out_y=py[4];
endmodule
