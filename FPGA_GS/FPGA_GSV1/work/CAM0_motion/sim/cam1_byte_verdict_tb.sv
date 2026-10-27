`timescale 1ns/1ps
module cam1_byte_verdict_tb;
 reg sc=0,vc=0,rst=0,vs=0,de=0,byte_error=0;
 always #10 sc=~sc;always #13.888888889 vc=~vc;
 wire result_valid;wire [7:0] errors;wire [255:0] status;wire snap;
 video_capture_status #(.SOURCE_ID(1),.CHECK_BYTE_ERRORS(1)) dut(
  .ref_clk(sc),.video_clk(vc),.rst_n(rst),.source_ready(rst),
  .video_vs(vs),.video_de(de),.byte_frame_error(byte_error),
  .snapshot_valid(snap),.snapshot(status),.frame_result_valid(result_valid),
  .frame_result_errors(errors));
 task idle(input integer n);repeat(n) @(negedge vc);endtask
 task complete_payload;
  begin
   vs=0;idle(25200);
   for(integer row=0;row<720;row++) begin de=1;idle(1280);de=0;idle(520);end
   idle(115200);
  end
 endtask
 integer verdicts=0;
 always @(posedge vc) if(result_valid) begin
  verdicts++;
  if(verdicts==1 && errors!=8'h20) $fatal(1,"complete geometry lost byte error %h",errors);
  if(verdicts==2 && errors!=0) $fatal(1,"byte error leaked into next frame %h",errors);
 end
 initial begin
  rst=1;#1;rst=0;#100;rst=1;idle(20);
  vs=1;idle(3600);complete_payload();
  byte_error=1;vs=1;idle(3600);
  if(status[119:112]!=8'h20 || status[95:64]!=921600 || status[111:96]!=720
    || status[159:128]!=0 || status[191:160]!=1) $fatal(1,"bad byte counted good %h",status);
  complete_payload();byte_error=0;vs=1;idle(3600);
  if(verdicts!=2 || status[119:112]!=0 || status[159:128]!=1 || status[191:160]!=1)
   $fatal(1,"valid frame did not recover %h",status);
  $display("PASS CAM1 byte validity: full921600/720 with odd-byte/overflow flag rejects as bit5 and bad-count;next full frame recovers;geometry remains enabled");
  $finish;
 end
 initial begin #90000000;$fatal(1,"byte verdict timeout");end
endmodule
