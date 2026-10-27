`timescale 1ns/1ps
module m34_hdmi_tb;
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 reg clk=0,refclk=0,rst=0;real half=6.734006734;
 always #(half) clk=~clk;always #10 refclk=~refclk;
 reg vs=0,hs=0,de=0;reg [7:0] r=0,g=0,b=0;
 wire ov,od,ok;wire [15:0] rgb;wire [31:0] received;
 hdmi_input dut(.clk(clk),.ref_clk(refclk),.rst_n(rst),.configured(1'b1),
 .vs(vs),.hs(hs),.de(de),.r(r),.g(g),.b(b),.out_vs(ov),.out_de(od),
 .rgb(rgb),.format_ok(ok),.received_frames(received),.input_beat());
 wire healthy,pipe_rst,verdict;wire [31:0] id,stamp,vid;wire [7:0] errors;
 video_capture_status monitor(.ref_clk(refclk),.video_clk(clk),.rst_n(rst),
 .source_ready(ok),.video_vs(ov),.video_de(od),.pipeline_rst_n(pipe_rst),
 .healthy(healthy),.frame_open_id(id),.frame_open_time(stamp),
 .frame_result_valid(verdict),.frame_result_id(vid),.frame_result_errors(errors));
 wire cv,cd;wire [15:0] cr;wire [31:0] ci,ct;
 capture_pipe pipe(.clk(clk),.rst_n(pipe_rst),.vs(ov),.de(od),.rgb(rgb),
 .frame_id(id),.frame_time(stamp),.out_vs(cv),.out_de(cd),.out_rgb(cr),.out_id(ci),.out_time(ct));
 reg [17:0] expected0,expected1;reg [17:0] cap0,cap1;
 integer pixels=0,checks=0,good_verdicts=0;
 always @(posedge clk) begin
  expected0<={vs,de,{r[7:3],g[7:2],b[7:3]}};expected1<=expected0;
  cap0<={ov,od,rgb};cap1<=cap0;
  if(verdict && errors==0) good_verdicts++;
  #0.1;
  if(rst && received>0) begin
   if({ov,od,rgb}!==expected1) $fatal(1,"HDMI_PAD_TUPLE latency/alignment");
   if(od) pixels++;
  end
  if(pipe_rst && cd && {cv,cd,cr}!==cap1) $fatal(1,"HDMI_CAPTURE_TUPLE latency/alignment");
 end
 task frame(input integer total);
  for(integer y=0;y<750;y++) for(integer x=0;x<total;x++) begin
   @(negedge clk);hs=x<40;vs=y<5;de=x>=260 && x<1540 && y>=25 && y<745;
   r=x;g=y;b=x^y;
  end
 endtask
 initial begin
  #100;rst=1;repeat(10) @(negedge clk);
  repeat(4) frame(1650);
  if(!ok || !healthy || good_verdicts<1) $fatal(1,"720p60 monitor not healthy geom=%b rate=%b frames=%0d",dut.geometry_ok,dut.rate_ok,good_verdicts);checks++;
  half=6.740740741; // 74.25MHz/1.001, unchanged 1650x750 totals
  repeat(4) frame(1650);
  if(!ok || !healthy) $fatal(1,"720p59.94 rejected");checks++;
  frame(1660);frame(1660);
  if(ok) $fatal(1,"bad line total accepted");checks++;
  @(negedge clk);vs=0;hs=0;de=0;
  #22000000;
  if(ok) $fatal(1,"lost sync remained accepted");checks++;
  $display("M34_HDMI_PASS checks=%0d pixels=%0d good_verdicts=%0d full720=1 rates60_5994=1 pad_tuple=1 capture_alignment=1",checks,pixels,good_verdicts);$finish;
 end
 initial begin #250000000;$fatal(1,"hdmi timeout");end
endmodule
