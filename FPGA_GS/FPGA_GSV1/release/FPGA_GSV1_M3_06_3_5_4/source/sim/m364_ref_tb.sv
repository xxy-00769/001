`timescale 1ns/1ps
module m364_ref_tb;
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 reg clk=0;always #10 clk=~clk;
 wire cfg,cam,ready;
 m364_ref_dividers dut(.clkin1(clk),.cfg_clk(cfg),.camera_clk(cam),.ready(ready));
 realtime cr=0,cf=0,mr=0,mf=0;
 integer cfg_cycles=0,cam_cycles=0;
 always @(posedge cfg) begin
  if(cr>0) begin
   if($realtime-cr!=100 || cr>0 && $realtime-cf!=60) $fatal(1,"cfg clock period/duty");
   cfg_cycles++;
  end
  cr=$realtime;
 end
 always @(negedge cfg) if(cr>0) begin
  if($realtime-cr!=40) $fatal(1,"cfg high width");cf=$realtime;
 end
 always @(posedge cam) begin
  if(mr>0) begin
   if($realtime-mr!=40 || $realtime-mf!=20) $fatal(1,"camera clock period/duty");
   cam_cycles++;
  end
  mr=$realtime;
 end
 always @(negedge cam) if(mr>0) begin
  if($realtime-mr!=20) $fatal(1,"camera high width");mf=$realtime;
 end
 initial begin
  #89;if(ready) $fatal(1,"early ready");
  #2;if(!ready) $fatal(1,"missing ready");
  #2000;if(cfg_cycles<19 || cam_cycles<49) $fatal(1,"missing clocks");
  $display("M364_REF_PASS cfg=10MHz duty=40/60 camera=25MHz duty=50/50 startup=5cycles");$finish;
 end
endmodule
