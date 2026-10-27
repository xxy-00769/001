`timescale 1ns/1ps
// Acknowledged bundled mailbox; the system payload is held until receipt.
// Frame-boundary consumers commit only the coherent, already received bundle.
module m2_view_select(input sys_clk,clk,rst_n,frame_sync,
 input [1:0] view_request,input [2:0] mode_request,
 output reg [1:0] selected_view,output reg [2:0] selected_mode);
 reg req,ack;reg [4:0] payload,received;reg [1:0] a_sync,r_sync;reg fs;
 always @(posedge sys_clk or negedge rst_n) begin
  if(!rst_n) begin req<=0;payload<=0;a_sync<=0;end
  else begin
   a_sync<={a_sync[0],ack};
   if(req==a_sync[1] && payload!={mode_request,view_request}) begin
    payload<={mode_request,view_request};req<=~req;
   end
  end
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin ack<=0;r_sync<=0;received<=0;fs<=0;selected_view<=0;selected_mode<=0;end
  else begin
   r_sync<={r_sync[0],req};fs<=frame_sync;
   if(r_sync[1]!=ack) begin received<=payload;ack<=r_sync[1];end
   if(frame_sync && !fs) begin selected_view<=received[1:0];selected_mode<=received[4:2];end
  end
 end
endmodule
