`timescale 1ns/1ps
module m2_hdmi_tb;
 reg clk=0,refclk=0,rst=0;always #6.734006734 clk=~clk;always #10 refclk=~refclk;
 reg vs=0,hs=0,de=0;reg [7:0] r=0,g=0,b=0;
 wire ov,od,ok;wire [15:0] rgb;wire [31:0] received;
 hdmi_input dut(.clk(clk),.ref_clk(refclk),.rst_n(rst),.configured(1'b1),
  .vs(vs),.hs(hs),.de(de),.r(r),.g(g),.b(b),.out_vs(ov),.out_de(od),.rgb(rgb),
  .format_ok(ok),.received_frames(received));
 integer pixels=0,checks=0;
 always @(posedge clk) if(rst) begin
  #1;
  if(od) begin
   if(!de || rgb!=={r[7:3],g[7:2],b[7:3]} || ov!==vs) $fatal(1,"RGB565/DE/VS alignment");pixels++;
  end
 end
 task frame(input integer total);
  integer y,x;
  begin
   for(y=0;y<750;y++) for(x=0;x<total;x++) begin
    @(negedge clk);hs=x<40;vs=y<5;de=x>=260 && x<1540 && y>=25 && y<745;
    r=x;g=y;b=x^y;
   end
  end
 endtask
 initial begin
  #100;rst=1;repeat(10) @(negedge clk);
  repeat(3) frame(1650);
  if(!ok) $fatal(1,"720p60 not accepted lines=%0d bad=%0d period=%0d geom=%b rate=%b",dut.lines,dut.bad_lines,dut.period,dut.geometry_ok,dut.rate_ok);checks++;
  frame(1660);frame(1660);
  if(ok) $fatal(1,"unsupported total accepted");checks++;
  repeat(3) frame(1650);
  if(!ok) $fatal(1,"reconnection failed");checks++;
  @(negedge clk);vs=0;hs=0;de=0;
  #22000000;
  if(ok) $fatal(1,"disconnected input stayed valid");checks++;
  $display("M2_HDMI_PASS checks=%0d pixels=%0d received=%0d clock=74.25MHz RGB565=1 unsupported_and_disconnect_recovery=1",checks,pixels,received);$finish;
 end
 initial begin #200000000;$fatal(1,"HDMI timeout");end
endmodule
