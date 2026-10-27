`timescale 1ns/1ps
module GRS_INST;wire GRSNET=1'b1;endmodule
// A discriminating model, not a measurement of sensor waveforms: default DVP
// diagram (datasheet fig5-7), two-line VS width (4709 default02), programmed
// HTS2172/VTS1322, 1280x720 RGB565. Test all four sync inversion combinations
// through production gearbox + geometry checker. Measured signature is 4344/1/03.
module cam3660_sync_signature_tb;
 reg pclk=0;always #6.944 pclk=~pclk;
 reg refclk=0;always #10 refclk=~refclk;
 reg rst_n=1,href=0,vs=0;reg [7:0] octet=0;
 wire [3:0] pc,de,ovs,bad,healthy,verdict;
 wire [15:0] rgb[0:3];wire [255:0] snapshot[0:3];wire [7:0] errors[0:3];
 integer results[0:3];integer expected_x=0,expected_y=0,expected_frame=0;
 integer counted=0;reg prev_vs=0,prev_de=0;
 function automatic [15:0] pixel(input integer f,y,x);
  pixel=(f*16'h2121)^(y*16'h31)^x;
 endfunction
 genvar g;
 generate for(g=0;g<4;g=g+1) begin: combination
  // bit0=VS inversion; bit1=HREF inversion. PCLK never changes.
  wire ivs=vs ^ ((g&1)!=0),ihref=href ^ ((g&2)!=0);
  cam3660_dvp dut(.pclk(pclk),.rst_n(rst_n),.de_i(ihref),.vs_i(ivs),.pdata_i(octet),
   .pixel_clk(pc[g]),.de_o(de[g]),.vs_o(ovs[g]),.frame_bad(bad[g]),.pdata_o(rgb[g]));
  video_capture_status #(.SOURCE_ID(1)) monitor(.ref_clk(refclk),.video_clk(pc[g]),
   .rst_n(rst_n),.source_ready(rst_n),.video_vs(ovs[g]),.video_de(de[g]),
   .pipeline_rst_n(),.healthy(healthy[g]),.timed_out(),.timeout_count(),
   .snapshot_valid(),.snapshot(snapshot[g]),.frame_open_id(),.frame_open_time(),
   .frame_result_valid(verdict[g]),.frame_result_id(),.frame_result_errors(errors[g]));
  initial results[g]=0;
  always @(posedge pc[g]) if(verdict[g]) results[g]=results[g]+1;
 end endgenerate
 task automatic cycles(input integer n);
  repeat(n) @(negedge pclk);
 endtask
 task automatic sync_pulse;
  begin href=0;vs=1;cycles(2*2172*2);vs=0;end
 endtask
 task automatic send_frame(input integer f);
  integer y,x;reg [15:0] value;
  begin
   sync_pulse();cycles(20*2172*2);
   for(y=0;y<720;y=y+1) begin
    for(x=0;x<1280;x=x+1) begin
     value=pixel(f,y,x);href=1;octet=value[15:8];cycles(1);
     octet=value[7:0];cycles(1);
    end
    href=0;octet=8'hd3;cycles((2172-1280)*2);
   end
   cycles((1322-2-20-720)*2172*2);
  end
 endtask
 always @(posedge pc[0]) if(rst_n) begin
  if(ovs[0]&&!prev_vs) begin expected_frame=expected_frame+1;expected_x=0;expected_y=0;end
  if(de[0]) begin
   if(rgb[0]!==pixel(expected_frame,expected_y,expected_x))
    $fatal(1,"RGB source/byte mismatch f%0d y%0d x%0d",expected_frame,expected_y,expected_x);
   expected_x=expected_x+1;counted=counted+1;
  end
  if(prev_de&&!de[0]) begin
   if(expected_x!=1280) $fatal(1,"normal line length %0d",expected_x);
   expected_x=0;expected_y=expected_y+1;
  end
  if(bad[0]) $fatal(1,"valid tuple byte/overflow error");
  prev_vs=ovs[0];prev_de=de[0];
 end
 integer i;
 initial begin
  #1;rst_n=0;cycles(16);rst_n=1;cycles(50);
  send_frame(1);send_frame(2);sync_pulse();cycles(100);
  for(i=0;i<4;i=i+1) begin
   $display("sync inversion %0d: pixels=%0d rows=%0d errors=%02h good=%0d bad=%0d verdicts=%0d",
    i,snapshot[i][95:64],snapshot[i][111:96],snapshot[i][119:112],
    snapshot[i][159:128],snapshot[i][191:160],results[i]);
   if(results[i]<2) $fatal(1,"missing repeated full-size frame reports");
  end
  if(snapshot[0][95:64]!=921600 || snapshot[0][111:96]!=720 || snapshot[0][119:112]!=0
   || snapshot[0][159:128]!=2 || counted!=2*921600)
    $fatal(1,"normal full frame not exactly 921600/720/00");
  if(snapshot[3][95:64]!=4344 || snapshot[3][111:96]!=1 || snapshot[3][119:112]!=3)
    $fatal(1,"measured 4344/1/03 signature not reproduced");
  for(i=1;i<3;i=i+1)
   if(snapshot[i][95:64]==4344 && snapshot[i][111:96]==1 && snapshot[i][119:112]==3)
    $fatal(1,"single inversion cannot distinguish measured signature");
  $display("PASS sync signature: full HTS2172/VTS1322, both-sync inversion alone reproduces measured 4344/1/03; normal sync yields 921600/720/00 with every independent RGB565 pixel correct; no guard disabled");
  $finish;
 end
 initial begin #180000000;$fatal(1,"signature simulation deadline");end
endmodule
