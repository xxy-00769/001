`timescale 1ns/1ps
module m3_right_owner_tb;
 reg c=0,pc=0,rst=0,fs=0,selected=0,begin_frame=0,publish=0;
 always #5 c=~c;always #16.923077 pc=~pc;
 wire ack,bank,ready;
 m3_right_store dut(.clk(c),.rst_n(rst),.pc(pc),.fs(fs),.selected(selected),.quarter(1'b0),.request(1'b0),
 .begin_frame(begin_frame),.publish(publish),.frame_id(32'd19),.begin_ack(ack),.write_bank(bank),.ready(ready),
 .de(),.pixel(),.araddr(),.arlen(),.arvalid(),.arready(1'b0),.rdata(256'd0),.rvalid(1'b0),.rlast(1'b0));
 task start_frame;begin
 @(negedge c);begin_frame=1;wait(ack);@(negedge c);begin_frame=0;repeat(5) @(negedge c);
 end endtask
 task sof;begin
 @(negedge pc);fs=1;repeat(3) @(negedge pc);fs=0;repeat(20) @(negedge c);
 end endtask
 reg complete_bank;
 initial begin
 #100;rst=1;start_frame;complete_bank=bank;
 publish=1;@(negedge c);publish=0;repeat(10) @(negedge c);
 if(!dut.pending) $fatal(1,"complete missing");
 start_frame;start_frame;
 if(!dut.pending || dut.pbank!=complete_bank || bank==complete_bank) $fatal(1,"aborted hidden frames retire last complete");
 selected=1;repeat(10) @(negedge c);sof;
 if(!dut.held || !dut.enabled || dut.rbank!=complete_bank) $fatal(1,"first select");
 selected=0;repeat(10) @(negedge c);
 if(dut.held || !dut.pending || dut.pbank!=complete_bank) $fatal(1,"hidden release loses complete descriptor");
 selected=1;repeat(10) @(negedge c);sof;
 if(!dut.held || !dut.enabled || dut.rbank!=complete_bank) $fatal(1,"reselect before next publish");
 start_frame;if(bank==dut.rbank) $fatal(1,"writes held bank");
 $display("M3_RIGHT_OWNER_PASS aborted_hidden_frames=2 last_complete_retained=1 reselect_before_publish=1 reader_pin=1");$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
