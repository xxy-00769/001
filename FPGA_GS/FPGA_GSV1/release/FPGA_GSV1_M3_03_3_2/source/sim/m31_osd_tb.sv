`timescale 1ns/1ps
module m31_osd_tb;
 reg clk=0;always #6.734006734 clk=~clk;
 reg [10:0] x=0,y=0;reg [2:0] view=0,mode=0,feedback=0;reg [3:0] hint=0,good=15;
 wire area,pixel;
 m31_osd dut(.clk(clk),.x(x),.y(y),.view(view),.mode(mode),.hint_visible(1'b1),.hint_code(hint),
  .video_good(good),.feedback(feedback),.area(area),.pixel(pixel));
 wire original_pixel;wire [10:0] col=x-dut.ox,row=y-dut.oy;
 m3_text original(.text_id(dut.text_id),.col(col[7:0]),.row(row[3:0]),.pixel(original_pixel));
 reg [1:0] ea=0,ep=0;integer checked=0,glyphs=0;
 always @(posedge clk) begin
  ea={ea[0],dut.area_raw};ep={ep[0],original_pixel};#1;
  if(checked>2 && (area!==ea[1] || (area && pixel!==ep[1]))) $fatal(1,"OSD pipeline mismatch");
  if(area && pixel) glyphs++;checked++;
 end
 wire ignored0,ignored1,ignored2,ignored3;wire [7:0] ignored_data,ignored_dev;wire [15:0] ignored_addr;
 ms7210_ctl #(.AVI_VIC(34)) tx(.clk(clk),.rstn(1'b0),.init_over(ignored0),.device_id(ignored_dev),.iic_trig(ignored1),
  .w_r(ignored2),.addr(ignored_addr),.data_in(ignored_data),.busy(1'b0),.data_out(8'd0),.byte_over(1'b0));
 integer v,m,f,yy,xx,bytesum,k;reg [23:0] command;
 initial begin
  bytesum=0;for(k=30;k<=46;k++) begin command=tx.cmd_data(k);bytesum+=command[7:0];end
  if(bytesum%256) $fatal(1,"AVI checksum");
  command=tx.cmd_data(37);if(command[7:0]!=34) $fatal(1,"AVI VIC");
  for(v=0;v<5;v++) for(m=0;m<5;m++) for(f=0;f<6;f++) begin
   view=v;mode=m;feedback=f;hint=(m%2 ? 5:6);good=f%2 ? 15:0;
   for(yy=0;yy<9;yy++) begin
    case(yy) 0:y=12;1:y=24;2:y=32;3:y=64;4:y=552;5:y=1052;6:y=160;7:y=700;8:y=340;endcase
    for(xx=0;xx<1920;xx++) begin x=xx;@(negedge clk);end
   end
  end
  repeat(4) @(negedge clk);
  if(glyphs==0) $fatal(1,"no glyphs");
  $display("M31_OSD_PASS samples=%0d glyph_pixels=%0d pipeline=2 real_font=1 AVI_VIC=34 checksum=1",checked,glyphs);$finish;
 end
endmodule
