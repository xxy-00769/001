`timescale 1ns/1ps
module GRS_INST;wire GRSNET=1'b1;endmodule
module cam3660_dvp_tb;
 reg pclk=0;always #6.944 pclk=~pclk; // selected sensor byte PCLK, nominal 72MHz
 reg rst_n=0,href=0,vs=0;reg [7:0] octet=0;
 wire pixel_clk,de,ovs,byte_bad;wire [15:0] rgb;
 cam3660_dvp dut(.pclk(pclk),.rst_n(rst_n),.de_i(href),.vs_i(vs),.pdata_i(octet),
  .pixel_clk(pixel_clk),.de_o(de),.vs_o(ovs),.frame_bad(byte_bad),.pdata_o(rgb));
 wire verdict_valid;wire [7:0] geometry_error;wire [31:0] verdict_id;
 wire [255:0] snapshot;
 wire pipeline_rst,healthy;
 reg refclk=0;always #10 refclk=~refclk;
 video_capture_status #(.SOURCE_ID(1)) monitor(.ref_clk(refclk),.video_clk(pixel_clk),
  .rst_n(rst_n),.source_ready(rst_n),.video_vs(ovs),.video_de(de),
  .pipeline_rst_n(pipeline_rst),.healthy(healthy),.timed_out(),.timeout_count(),
  .snapshot_valid(),.snapshot(snapshot),.frame_open_id(),.frame_open_time(),
  .frame_result_valid(verdict_valid),.frame_result_id(verdict_id),.frame_result_errors(geometry_error));
 reg vs_old=0,closed_bad=0;
 always @(posedge pixel_clk or negedge rst_n)
  if(!rst_n) begin vs_old<=0;closed_bad<=0;end
  else begin vs_old<=ovs;if(ovs&&!vs_old) closed_bad<=byte_bad;end
 wire [7:0] protected_error=geometry_error | {7'd0,closed_bad};
 function automatic [15:0] expected_pixel(input integer f,y,x);
  expected_pixel=((f*16'h2121) ^ (y*16'h31) ^ x);
 endfunction
 task automatic idle(input integer n);
  repeat(n) @(negedge pclk);
 endtask
 task automatic send_frame(input integer f,kind);
  integer y,x,w;reg [15:0] v;
  begin
   vs=1;href=0;idle(12);vs=0;idle(23+(f%2));
   for(y=0;y<720;y=y+1) begin
    w=(kind==2 && y==211) ? 1279:1280;
    for(x=0;x<w;x=x+1) begin
     v=expected_pixel(f,y,x);
     href=1;octet=v[15:8];idle(1);octet=v[7:0];idle(1);
    end
    if(kind==1 && y==317) begin octet=8'hfa;idle(1);end
    href=0;octet=8'hd3;idle(27+(y%3));
   end
   idle(70);
  end
 endtask
 integer observed_frame=0,x=0,y=0,pixels=0,results=0;
 integer pixel_edges=0;
 always @(posedge pixel_clk) pixel_edges=pixel_edges+1;
 reg prev_vs=0,prev_de=0;
 always @(posedge pixel_clk) if(rst_n) begin
  if(ovs&&!prev_vs) begin
   if(observed_frame>0) begin
    if(y!=720 || pixels!=((observed_frame==3) ? 921599:921600))
     $fatal(1,"frame dimensions f%0d rows%0d pixels%0d",observed_frame,y,pixels);
   end
   observed_frame=observed_frame+1;x=0;y=0;pixels=0;
  end
  if(de) begin
   if(ovs || observed_frame==0) $fatal(1,"DE outside open frame");
   if(rgb!==expected_pixel(observed_frame,y,x))
    $fatal(1,"pixel mismatch frame=%0d row=%0d col=%0d expected=%h actual=%h",observed_frame,y,x,expected_pixel(observed_frame,y,x),rgb);
   x=x+1;pixels=pixels+1;
  end
  if(prev_de&&!de) begin
   if(x!=((observed_frame==3 && y==211) ? 1279:1280)) $fatal(1,"line size f%0d y%0d x%0d",observed_frame,y,x);
   x=0;y=y+1;
  end
  prev_vs=ovs;prev_de=de;
  if(verdict_valid) begin
   results=results+1;
   if(results==2 && (geometry_error!=0 || !closed_bad || protected_error==0))
    $fatal(1,"odd byte complete geometry must still reject frame");
   if(results==3 && (geometry_error==0 || protected_error==0)) $fatal(1,"short line accepted");
   if((results==1 || results==4) && protected_error!=0)
    $fatal(1,"valid/recovery frame rejected %0d error %h",results,protected_error);
  end
 end
 initial begin
  // Explicit assertion edge also resets the sink while its divided clock is
  // stopped; a declaration initializer alone is not a simulated reset pulse.
  rst_n=1;#1;rst_n=0;idle(16);rst_n=1;idle(50);
  send_frame(1,0);send_frame(2,1);send_frame(3,2);send_frame(4,0);
  vs=1;idle(80);
  if(results!=4) $fatal(1,"missing frame verdicts %0d",results);
  // Reset in the middle of a byte discards the old half/clock/FIFO state.
  vs=0;href=1;octet=8'hdd;idle(1);rst_n=0;idle(8);
  if(de!==0 || ovs!==0) $fatal(1,"reset did not suppress tuples");
  $display("PASS CAM1 full 1280x720 RGB565: every independent frame/row/column pixel, both byte/divider phases, odd HREF/blank phases, repeated FIFO wrap, odd byte rejection, short line rejection, next full-frame recovery, tuple-aligned VS/DE and reset");
  $finish;
 end
 initial begin #250000000;$fatal(1,"capture deadline");end
 initial begin
  #100000;
  if(pixel_edges<100 || observed_frame==0)
   $fatal(1,"clock/tuple startup edges=%0d frames=%0d resets=%b/%b ptrs=%h/%h sync=%h/%h opened=%b ovs=%b",pixel_edges,observed_frame,dut.source_reset,dut.sink_reset,dut.wr_gray,dut.rd_gray,dut.wg2,dut.rg2,dut.opened,ovs);
 end
endmodule
