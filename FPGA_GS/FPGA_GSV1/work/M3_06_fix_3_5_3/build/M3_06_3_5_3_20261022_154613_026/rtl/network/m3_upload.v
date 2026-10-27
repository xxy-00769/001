`timescale 1ns/1ps
// Bounded one-fragment staging RAM. DDR has no return backpressure; the entire
// 40-beat fragment fits before any native request is exposed. One reader pin
// spans a frame and is released only after the last DDR burst drains/stages.
module m3_upload(input clk,rst_n,online,input tick_ms,input [7:0] fps,
 output reg acquire,release_frame,input grant,held,input [1:0] bank,
 input [31:0] identity,stamp,
 output reg fragment_ready,input fragment_taken,
 output reg [31:0] frame_id,frame_time,offset,output reg [15:0] index,
 input [8:0] word_addr,output [31:0] word_data,
 output reg [27:0] araddr,output reg [3:0] arlen,output arvalid,input arready,
 input [255:0] rdata,input rvalid,rlast,
 output reg [31:0] frames,aborts);
 reg [15:0] interval_ms;
 always @* begin if(fps>=30) interval_ms=34;else if(fps>=15) interval_ms=67;else if(fps>=10) interval_ms=100;else interval_ms=200;end
 reg [3:0] state;reg [15:0] age;reg [1:0] burst;reg [8:0] wa;reg [27:0] base;
 localparam IDLE=0,ACQUIRE=1,ADDR=2,RETURN=3,READY=4,DRAIN=5;
 assign arvalid=state==ADDR;
 rd_fram_buf staging(.wr_clk(clk),.wr_rst(!rst_n),.wr_en(rvalid),.wr_addr(wa),.wr_data(rdata),
 .rd_clk(clk),.rd_rst(!rst_n),.rd_addr({3'd0,word_addr}),.rd_data(word_data));
 always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin state<=0;acquire<=0;release_frame<=0;fragment_ready<=0;
 araddr<=0;arlen<=0;frame_id<=0;frame_time<=0;offset<=0;index<=0;age<=1000;
 burst<=0;wa<=0;base<=0;frames<=0;aborts<=0;end
 else begin
 acquire<=0;release_frame<=0;
 if(tick_ms && age!=65535) age<=age+1'b1;
 if(rvalid) wa<=wa+1'b1;
 case(state)
 IDLE:if(online && fps!=0 && age>=interval_ms) begin acquire<=1;state<=ACQUIRE;end
 ACQUIRE:begin
  if(grant) begin
   frame_id<=identity;frame_time<=stamp;offset<=0;index<=0;age<=0;
   base<=bank==2 ? 28'h2000000 : {5'd0,bank[0],22'd0};
   araddr<=bank==2 ? 28'h2000000 : {5'd0,bank[0],22'd0};arlen<=15;burst<=0;wa<=0;state<=ADDR;
  end else if(!online) state<=IDLE;
  else acquire<=1;
 end
 ADDR:if(arready) begin
   // First return may coincide with address acceptance.
   if(rvalid && rlast) state<=DRAIN;else state<=RETURN;
 end
 RETURN:if(rvalid && rlast) state<=DRAIN;
 DRAIN:begin
  if(!online) begin release_frame<=1;fragment_ready<=0;aborts<=aborts+1'b1;state<=IDLE;end
  else if(burst==2) begin fragment_ready<=1;state<=READY;end
  else begin burst<=burst+1'b1;araddr<=araddr+128;arlen<=burst==1 ? 7 : 15;state<=ADDR;end
 end
 READY:begin
  if(!online) begin fragment_ready<=0;release_frame<=1;aborts<=aborts+1'b1;state<=IDLE;end
  else if(fragment_taken) begin
   fragment_ready<=0;
   if(index==1439) begin release_frame<=1;frames<=frames+1'b1;state<=IDLE;end
   else begin index<=index+1'b1;offset<=offset+1280;
    araddr<=base+(offset>>2)+320;arlen<=15;burst<=0;wa<=0;state<=ADDR;end
  end
 end
 endcase
 end end
endmodule
