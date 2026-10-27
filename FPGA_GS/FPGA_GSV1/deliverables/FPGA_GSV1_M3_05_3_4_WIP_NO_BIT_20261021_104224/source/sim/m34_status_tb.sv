`timescale 1ns/1ps
module m34_status_tb;
 reg clk=0;always #10 clk=~clk;
 reg rst=0,cfg=0,hb=0,fr=0,pub=0,beat_enable=0,frame_enable=0,pub_enable=0,fmt=0,cap=0,ready=0,fault=0;
 integer cycles=0;
 always @(negedge clk) begin
  cycles++;
  if(beat_enable && cycles%4==0) hb=~hb;
  if(frame_enable && cycles%16==0) fr=~fr;
  if(pub_enable && cycles%32==0) pub=~pub;
 end
 wire [2:0] stage;
 m34_hdmi_status #(.MS_CYCLES(20)) status(.clk(clk),.rst_n(rst),.configured(cfg),
 .input_beat(hb),.frame_toggle(fr),.format_ok(fmt),.capture_ok(cap),
 .published_toggle(pub),.has_frame(ready),.display_fault(fault),.stage(stage));
 task expect_stage(input integer n);
  repeat(70) @(negedge clk);
  if(stage!==n[2:0]) $fatal(1,"stage got=%0d expected=%0d",stage,n);
 endtask
 reg [10:0] x=0,y=0;reg [2:0] shown=0;
 wire area,pixel;
 m31_osd osd(.clk(clk),.x(x),.y(y),.view(3'd2),.mode(3'd0),
 .hint_visible(1'b0),.hint_code(4'd0),.video_good(4'b0000),.feedback(3'd0),
 .hdmi_stage(shown),.area(area),.pixel(pixel));
 reg [31:0] hashes[0:7];integer lit=0;
 reg stream=0;integer stream_count=0;reg [1:0] expected_area,expected_pixel;
 function expected_dot(input [2:0] n,input integer cx,cy);
  reg [14:0] bitmap;integer dx,dy;
  begin
   case(n)
    0:bitmap=15'b111_101_101_101_111;1:bitmap=15'b010_110_010_010_111;
    2:bitmap=15'b111_001_111_100_111;3:bitmap=15'b111_001_111_001_111;
    4:bitmap=15'b101_101_111_001_001;5:bitmap=15'b111_100_111_001_111;
    6:bitmap=15'b111_100_111_101_111;7:bitmap=15'b111_001_001_001_001;
   endcase
   dx=cx-332;dy=cy-340;expected_dot=0;
   if(dx>=0 && dx<32 && dy>=0 && dy<10) begin
    if(dx<6) expected_dot=dx<2 || dy>=8;
    else if(dx>=10 && dx<16) expected_dot=bitmap[14-(dy/2)*3-(dx-10)/2];
   end
  end
 endfunction
 always @(posedge clk) if(stream) begin
  expected_area<={expected_area[0],x>=332 && x<364 && y>=340 && y<356};
  expected_pixel<={expected_pixel[0],expected_dot(shown,x,y)};
  stream_count++;#1;
  if(stream_count>2 && (area!==expected_area[1] || (area && pixel!==expected_pixel[1])))
   $fatal(1,"streaming diagnostic pixel/area alignment");
 end
 initial begin
  repeat(3) @(negedge clk);rst=1;expect_stage(0);
  cfg=1;expect_stage(1);
  beat_enable=1;expect_stage(2);
  frame_enable=1;expect_stage(3);
  fmt=1;expect_stage(4);
  cap=1;expect_stage(5);
  ready=1;pub_enable=1;expect_stage(7);
  fault=1;expect_stage(6);
  fault=0;expect_stage(7);
  beat_enable=0;expect_stage(1);
  beat_enable=1;expect_stage(7);
  for(integer s=0;s<8;s++) begin
   shown=s;hashes[s]=0;lit=0;
   for(integer row=0;row<16;row++) for(integer col=0;col<32;col++) begin
    @(negedge clk);x=332+col;y=340+row;
    repeat(3) @(negedge clk);
    if(!area || osd.text_id!=0) $fatal(1,"left diagnostic area/text");
    hashes[s]=(hashes[s]*32'd16777619) ^ (pixel ? 32'h04c11db7 : 0);lit+=pixel;
   end
   if(lit==0) $fatal(1,"blank left status code");
   for(integer k=0;k<s;k++) if(hashes[k]==hashes[s]) $fatal(1,"indistinguishable left status");
  end
  stream=1;
  for(integer s=0;s<8;s++) begin
   @(negedge clk);shown=s;x=0;y=340;stream_count=0;
   repeat(4) @(negedge clk);
   for(integer row=0;row<16;row++) for(integer col=0;col<40;col++) begin
    x=328+col;y=340+row;@(negedge clk);
   end
  end
  $display("M34_STATUS_PASS stages=8 clock_loss_recovery=1 visible_codes=8 streaming_pipeline=2 resolution_blame_removed=1");$finish;
 end
endmodule
