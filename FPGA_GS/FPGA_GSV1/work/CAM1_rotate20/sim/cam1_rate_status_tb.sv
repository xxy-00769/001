`timescale 1ns/1ps
module cam1_rate_status_tb;
 reg sc=0,bc=0,dc=0,vc=0,rst=0,visible=1;
 always #10 sc=~sc;always #6.944444444 bc=~bc;
 always #5 dc=~dc;always #3.367003367 vc=~vc;
 reg [31:0] pub=0,disp=0;wire [31:0] counts,ms,hz;
 // Shorten only the observation interval to1ms (50000 reference cycles).
 // Production PCLK/reference/CDC clock ratios are unchanged.
 cam1_rate_status #(.REF_HZ(50000)) dut(.sc(sc),.pclk(bc),.dc(dc),.vc(vc),.rst_n(rst),
  .visible(visible),.published(pub),.displayed(disp),.counts(counts),.milliseconds(ms),.pclk_hz(hz));
 initial begin
  rst=1;#1;rst=0;#100;rst=1;
  #3100000;
  if(hz<71744 || hz>72256) $fatal(1,"actual PCLK/reference frequency window %0d",hz);
  @(negedge dc);pub=32'hffff;
  @(negedge vc);disp=32'hfffe;
  #5000;
  if(counts!==32'hffff0001) $fatal(1,"counter mailbox %h",counts);
  @(negedge dc);pub=32'h10000;
  @(negedge vc);disp=32'h10001;
  #5000;
  if(counts!==32'h00000002) $fatal(1,"counter wrap %h",counts);
  @(negedge vc);visible=0;disp=32'h10002;
  #5000;if(counts!==32'h00000002) $fatal(1,"masked image counted %h",counts);
  @(negedge vc);visible=1;
  #5000;if(counts!==32'h00000002) $fatal(1,"repeated image counted on unmask");
  @(negedge vc);disp=32'h10003;
  #5000;if(counts!==32'h00000003) $fatal(1,"visible new image not counted");
  // Prescaler wraps every256 byte clocks. Exercise stopped PCLK detection:
  // zero can only be asserted after a complete measurement window.
  force dut.byte_count=8'd0;
  #3100000;
  if(hz!=0) $fatal(1,"stopped PCLK %0d",hz);
  release dut.byte_count;
  #2100000;
  if(hz<71744 || hz>72256) $fatal(1,"returning PCLK %0d",hz);
  rst=0;#100;if(hz!=0 || counts!=0 || ms!=0) $fatal(1,"reset");
  $display("PASS CAM1 passive /256 frequency CDC,2-stage sampling,stopped/returning clock,publication/display16bit mailbox wrap,reset");
  $finish;
 end
endmodule
