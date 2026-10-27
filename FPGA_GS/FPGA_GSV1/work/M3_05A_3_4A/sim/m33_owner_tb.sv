`timescale 1ns/1ps
module m33_owner_tb;
 reg c=0,pc=0,rst=0,fs=0,selected=0,begin_frame=0,publish=0;
 always #5 c=~c;always #3.367003367 pc=~pc;
 wire ack,ready;wire [1:0] bank;
 wire av;wire [3:0] al;reg [4:0] remaining=0;
 always @(posedge c) if(!rst) remaining<=0;
 else if(av) remaining<=al+1'b1;else if(remaining!=0) remaining<=remaining-1'b1;
 m3_right_store #(.HD_DISPLAY(1)) dut(.clk(c),.rst_n(rst),.pc(pc),.fs(fs),.selected(selected),.quarter(1'b0),.request(1'b0),
 .begin_frame(begin_frame),.publish(publish),.frame_id(32'd19),.begin_ack(ack),.write_bank(bank),.ready(ready),
 .de(),.pixel(),.araddr(),.arlen(al),.arvalid(av),.arready(1'b1),.rdata(256'd0),.rvalid(remaining!=0),.rlast(remaining==1));
 task start_frame;begin
 @(negedge c);begin_frame=1;wait(ack);@(negedge c);begin_frame=0;repeat(5) @(negedge c);
 end endtask
 task sof;begin
 @(negedge pc);fs=1;repeat(3) @(negedge pc);fs=0;repeat(20) @(negedge c);
 end endtask
 integer bank2_reads=0;
 always @(posedge c) if(rst && av) begin
  if((dut.araddr>>22)!=(dut.rbank==2 ? 9 : 6+dut.rbank)) $fatal(1,"RIGHT native bank address alias bank=%0d addr=%h",dut.rbank,dut.araddr);
  if(dut.rbank==2) bank2_reads++;
 end
 integer quiet;integer stage=0;reg [1:0] complete_bank;
 initial begin
 #100;rst=1;start_frame;complete_bank=bank;
 publish=1;@(negedge c);publish=0;repeat(10) @(negedge c);
 if(!dut.pending) $fatal(1,"complete missing");
 start_frame;start_frame;
 if(!dut.pending || dut.pbank!=complete_bank || bank==complete_bank) $fatal(1,"aborted hidden frames retire last complete");
 stage=1;selected=1;repeat(10) @(negedge c);sof;
 if(!dut.held || !dut.enabled || dut.rbank!=complete_bank) $fatal(1,"first select");
 stage=2;selected=0;repeat(500) @(negedge c);
 if(dut.held || !dut.pending || dut.pbank!=complete_bank) $fatal(1,"hidden release loses complete descriptor");
 stage=3;selected=1;repeat(10) @(negedge c);sof;
 if(!dut.held || !dut.enabled || dut.rbank!=complete_bank) $fatal(1,"reselect before next publish");
 stage=4;start_frame;if(bank==dut.rbank) $fatal(1,"writes held bank");
 // A third frame can start while the reader and pending frame stay pinned.
 publish=1;@(negedge c);publish=0;repeat(5) @(negedge c);
 stage=5;begin_frame=1;repeat(8) @(negedge c);
 if(bank==dut.rbank || bank==dut.pbank) $fatal(1,"third slot overlaps pin");
 @(negedge c);begin_frame=0;
 stage=6;quiet=0;while(quiet<50) begin @(negedge c);if(!dut.busy && dut.cmdready) quiet++;else quiet=0;end;sof;
 if(bank==dut.rbank) $fatal(1,"post SOF write pin collision");
 // Walk begin request phases across the synchronized SOF pulse. Keep
 // display and pending simultaneously referenced; allocation must stay bounded.
 for(integer phase=0;phase<20;phase++) begin
  start_frame;publish=1;@(negedge c);publish=0;repeat(5) @(negedge c);
  fork
   begin repeat(phase) @(negedge c);sof;end
   begin
    repeat(10) @(negedge c);begin_frame=1;quiet=0;
    while(!ack && quiet<12) begin @(negedge c);quiet++;end
    if(!ack) $fatal(1,"SOF phase stalls ingress phase=%0d",phase);
    if(dut.held && bank==dut.rbank || dut.pending && bank==dut.pbank) $fatal(1,"pin overlap phase=%0d",phase);
    begin_frame=0;
   end
  join
 end
 if(bank2_reads==0) $fatal(1,"third slot native read not covered");
 $display("M33_OWNER_PASS third_slot=1 sof_phases=20 begin_ack_bound_cycles=12 held_pending_pins=1 hidden_abort_reselect=1");$finish;
 end
 initial begin #1000000;$fatal(1,"owner timeout stage=%0d",stage);end
endmodule
