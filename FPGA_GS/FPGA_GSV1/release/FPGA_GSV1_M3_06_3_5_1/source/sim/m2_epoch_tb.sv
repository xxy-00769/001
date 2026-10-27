`timescale 1ns/1ps
module m2_epoch_tb;
 reg dc=0,pc=0,rst=0,fs=0,enable=0,ready=1,done=0,valid=0;
 always #5 dc=~dc;always #16.923077 pc=~pc;
 wire req,sof;wire [27:0] addr;
 m2_rd_buf dut(.ddr_clk(dc),.ddr_rstn(rst),.vout_clk(pc),.rd_fsync(fs),.rd_en(1'b0),
  .quarter(1'b0),.selected(1'b1),.enabled(enable),.vout_de(),.vout_data(),
  .ddr_rreq(req),.ddr_raddr(addr),.ddr_rd_len(),.ddr_rrdy(ready),.ddr_rdone(done),
  .ddr_rdata({256{1'b1}}),.ddr_rdata_en(valid),.frame_start_event(sof));
 initial begin
  #100;@(negedge dc);rst=1;enable=1;wait(req);@(negedge dc);ready=0;
  // First command is still outstanding when a new display frame starts.
  fs=1;wait(sof);@(negedge dc);enable=0;repeat(10) @(negedge dc);fs=0;
  for(integer k=0;k<80;k++) begin valid=1;@(negedge dc);end
  valid=0;done=1;@(negedge dc);done=0;repeat(3) @(negedge dc);
  if(dut.wr_addr!==0 || addr!==0)
   $fatal(1,"OLD_RETURN_RESET: drained stale line changed new epoch ptr wr=%0d addr=%0d",dut.wr_addr,addr);
  $display("M2_EPOCH_PASS old_return_discarded=80 reset_after_drain=1");$finish;
 end
endmodule
