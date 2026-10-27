`timescale 1ns/1ps
// Bundled mailbox, held through acknowledgement. A newer event replaces the
// queued message if one is already in flight (human events are >=20 ms apart).
module m1_hint_cdc #(parameter HOLD_CYCLES=59090908)(
 input sys_clk,pix_clk,rst_n,event_in,input [3:0] code_in,
 output reg [3:0] code,output wire visible
);
 reg req,ack; reg [3:0] payload,queued; reg pending;
 reg [1:0] ack_s,req_s;
 localparam HOLD_WIDTH=$clog2(HOLD_CYCLES+1)>0 ? $clog2(HOLD_CYCLES+1) : 1;
 reg [HOLD_WIDTH-1:0] remaining;
 assign visible=remaining!=0;
 always @(posedge sys_clk or negedge rst_n) begin
  if(!rst_n) begin req<=0;payload<=0;queued<=0;pending<=0;ack_s<=0;end
  else begin
   ack_s<={ack_s[0],ack};
   if(event_in) begin queued<=code_in;pending<=1;end
   if(req==ack_s[1] && pending) begin
    payload<=queued;req<=~req;
    if(!event_in) pending<=0;
   end
  end
 end
 always @(posedge pix_clk or negedge rst_n) begin
  if(!rst_n) begin req_s<=0;ack<=0;code<=0;remaining<=0;end
  else begin
   req_s<={req_s[0],req};
   if(req_s[1]!=ack) begin
    code<=payload;remaining<=HOLD_CYCLES;ack<=req_s[1];
   end else if(remaining!=0) remaining<=remaining-1'b1;
  end
 end
endmodule
