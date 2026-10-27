`timescale 1ns/1ps
module m32_hint_tb;
 reg sc=0,pc=0,rst=0,event_in=0;reg [3:0] code_in=0;
 always #10 sc=~sc;always #3.367003367 pc=~pc;
 wire visible,long_visible;wire [3:0] code,long_code;
 m1_hint_cdc #(.HOLD_CYCLES(16)) short_timer(.sys_clk(sc),.pix_clk(pc),.rst_n(rst),
  .event_in(event_in),.code_in(code_in),.visible(visible),.code(code));
 m1_hint_cdc #(.HOLD_CYCLES(297000000)) board_timer(.sys_clk(sc),.pix_clk(pc),.rst_n(rst),
  .event_in(event_in),.code_in(code_in),.visible(long_visible),.code(long_code));
 task event_code(input [3:0] c);begin
  @(negedge sc);code_in=c;event_in=1;@(negedge sc);event_in=0;
  wait(code==c && long_code==c);#0.1;
 end endtask
 initial begin
  #100;rst=1;event_code(5);
  if(!visible || !long_visible || board_timer.remaining!=297000000 || $bits(board_timer.remaining)!=29)
   $fatal(1,"148.5MHz two-second timer truncated");
  // Let mailbox acknowledgement return, then refresh a visible hint.
  repeat(3) @(negedge sc);event_code(6);
  if(short_timer.remaining!=16) $fatal(1,"new event failed to refresh");
  repeat(15) begin @(posedge pc);#0.1;if(!visible) $fatal(1,"hint expired early");end
  @(posedge pc);#0.1;if(visible) $fatal(1,"hint failed expiry");
  $display("M32_HINT_PASS timer_width=29 board_cycles=297000000 seconds=2 refresh=1 expiry=1");$finish;
 end
 initial begin #10000;$fatal(1,"hint timeout");end
endmodule
