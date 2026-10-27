`timescale 1ns/1ps
module m2_processing_tb;
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 reg clk=0,rst=0;always #5 clk=~clk;
 reg [23:0] rgb=0;reg [9:0] x=0;reg [8:0] y=0;reg q=0;reg [2:0] mode=0;
 reg de=0,hs=0,vs=0,image=0;
 wire [23:0] result;wire oh,ov,od,oi;wire [9:0] ox;wire [8:0] oy;
 m2_processing dut(.clk(clk),.rst_n(rst),.rgb(rgb),.x(x),.y(y),.quad(q),.mode(mode),
  .de(de),.hs(hs),.vs(vs),.image(image),.out_rgb(result),.out_x(ox),.out_y(oy),
  .out_de(od),.out_hs(oh),.out_vs(ov),.out_image(oi));
 reg [23:0] want=0;
 reg [23:0] expected[0:3];reg [9:0] ex[0:3];reg [8:0] ey[0:3];
 reg [3:0] ed=0,eh=0,ev=0;integer checked=0;
 always @(posedge clk) if(rst) begin
  for(integer k=3;k>0;k--) begin expected[k]=expected[k-1];ex[k]=ex[k-1];ey[k]=ey[k-1];end
  expected[0]=want;ex[0]=x;ey[0]=y;ed={ed[2:0],de};eh={eh[2:0],hs};ev={ev[2:0],vs};
  #1;
  if(od!==ed[3] || oi!==ed[3] || oh!==eh[3] || ov!==ev[3]) $fatal(1,"metadata pipeline");
  if(od) begin
   if(ox!==ex[3] || oy!==ey[3] || result!==expected[3])
    $fatal(1,"processing mismatch sample=%0d x=%0d y=%0d got=%h expected=%h mode=%0d",checked,ox,oy,result,expected[3],mode);
   checked++;
  end
 end
 integer f,n,iq,im,ix,iy,lines=0;reg [23:0] ir,ie;
 initial begin
  for(integer k=0;k<4;k++) begin expected[k]=0;ex[k]=0;ey[k]=0;end
  #50;@(negedge clk);rst=1;
  f=$fopen("processing_vectors.txt","r");
  while(!$feof(f)) begin
   n=$fscanf(f,"%d %d %d %d %h %h\n",iq,im,ix,iy,ir,ie);
   if(n!=6) $fatal(1,"bad vector");
   q=iq;mode=im;x=ix;y=iy;rgb=ir;want=ie;
   de=ix>=80;image=de;hs=!de;vs=!de && iy==0;
   @(negedge clk);lines++;
  end
  de=0;image=0;repeat(8) @(negedge clk);
  $display("M2_PROCESSING_PASS samples=%0d cycles=%0d exact_fixed_point=1 seams=horizontal_and_vertical modes=5 latency=4",checked,lines);$finish;
 end
endmodule
