`timescale 1ns/1ps
// A narrow decode hazard wholly between pixel edges is not a pixel-domain
// line boundary. The DDR credit counter must not invent an extra line.
module m32_cdc_tb #(parameter FRAME_GLITCH=0);
 reg dc=0,pc=0,rst=0,enable=0,fs=0;
 always #5 dc=~dc;always #3.367003367 pc=~pc;
 m31_rd_buf dut(.ddr_clk(dc),.ddr_rstn(rst),.vout_clk(pc),.rd_fsync(fs),.rd_en(enable),
  .quarter(1'b0),.selected(1'b0),.enabled(1'b0),.vout_de(),.vout_data(),
  .ddr_rreq(),.ddr_raddr(),.ddr_rd_len(),.ddr_rrdy(1'b1),.ddr_rdone(1'b0),
  .ddr_rdata(256'd0),.ddr_rdata_en(1'b0),.frame_start_event());
 integer pixel_sofs=0,ddr_sofs=0;reg fs_previous=0;
 always @(posedge dc) if(rst && dut.frame_start_event) ddr_sofs++;
 integer pixel_line_starts=0;reg en_previous=0;
 always @(posedge pc) if(rst) begin
  if(enable && !en_previous) pixel_line_starts++;
  en_previous<=enable;
  if(fs && !fs_previous) pixel_sofs++;fs_previous<=fs;
 end
 initial begin
  #50;rst=1;#50;enable=!FRAME_GLITCH;
  #244;if(FRAME_GLITCH) fs=1;else enable=0;
  #2;if(FRAME_GLITCH) fs=0;else enable=1; // ns344..346; DDR samples at345, pixel sees no change
  #154;enable=0;#100;
  if(pixel_line_starts!=(FRAME_GLITCH ? 0:1) || dut.consumed!==pixel_line_starts)
   $fatal(1,"CDC_CREDIT_FALSE_ROW pixel_lines=%0d ddr_credit=%0d",pixel_line_starts,dut.consumed);
  if(ddr_sofs!=pixel_sofs) $fatal(1,"CDC_FALSE_SOF pixel_sofs=%0d ddr_sofs=%0d",pixel_sofs,ddr_sofs);
  $display("M32_CDC_PASS pixel_lines=%0d ddr_credit=%0d glitch_ns=2",pixel_line_starts,dut.consumed);$finish;
 end
endmodule
