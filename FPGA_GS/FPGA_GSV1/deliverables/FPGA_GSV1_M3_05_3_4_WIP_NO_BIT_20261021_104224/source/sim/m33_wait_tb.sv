`timescale 1ns/1ps
module m33_wait_tb;
 reg c=0,pc=0,rst=0,fs=0,selected=0,begin_frame=0,publish=0;
 always #5 c=~c;always #16.923077 pc=~pc;
 wire ack,bank,ready;
 wire av;wire [3:0] al;reg [4:0] remaining=0;
 always @(posedge c) if(!rst) remaining<=0;
 else if(av) remaining<=al+1'b1;else if(remaining!=0) remaining<=remaining-1'b1;
 m3_right_store dut(.clk(c),.rst_n(rst),.pc(pc),.fs(fs),.selected(selected),.quarter(1'b0),.request(1'b0),
 .begin_frame(begin_frame),.publish(publish),.frame_id(32'd19),.begin_ack(ack),.write_bank(bank),.ready(ready),
 .de(),.pixel(),.araddr(),.arlen(al),.arvalid(av),.arready(1'b1),.rdata(256'd0),.rvalid(remaining!=0),.rlast(remaining==1));
 task start_frame;begin
 @(negedge c);begin_frame=1;wait(ack);@(negedge c);begin_frame=0;repeat(5) @(negedge c);
 end endtask
 task sof;begin
 @(negedge pc);fs=1;repeat(3) @(negedge pc);fs=0;repeat(20) @(negedge c);
 end endtask
 integer quiet;integer stage=0;reg complete_bank;
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
 // A complete waiting frame must reach the selected reader before reuse.
 publish=1;@(negedge c);publish=0;repeat(5) @(negedge c);
 stage=5;begin_frame=1;repeat(20) @(negedge c);if(ack) $fatal(1,"expected baseline wait absent");
 $display("M33_BASELINE_WAIT_CONFIRMED held+pending begin blocked, next SOF required; 60Hz worst phase=16.667ms > four packets at5fps=0.556ms");
 stage=6;quiet=0;while(quiet<50) begin @(negedge c);if(!dut.busy && dut.cmdready) quiet++;else quiet=0;end;sof;wait(ack);@(negedge c);begin_frame=0;
 if(bank==dut.rbank) $fatal(1,"post SOF write pin collision");
 $display("M3_RIGHT_OWNER_PASS aborted_hidden_frames=2 last_complete_retained=1 reselect_before_publish=1 reader_pin=1");$finish;
 end
 initial begin #100000;$fatal(1,"timeout stage=%0d held=%b pending=%b busy=%b ready=%b sof=%b ack=%b av=%b remaining=%0d",stage,dut.held,dut.pending,dut.busy,dut.cmdready,dut.sof,ack,av,remaining);end
endmodule
