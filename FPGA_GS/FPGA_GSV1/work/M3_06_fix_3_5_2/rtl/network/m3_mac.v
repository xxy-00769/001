`timescale 1ns/1ps
// GMII frame store. CRC checked before publication. Four bounded RX slots;
// req/ack are per-slot toggles, descriptor length held until consumer ACK.
module m3_mac(input nc,nrst,input [7:0] rxd,input rxv,rxe,
 output reg [7:0] txd,output reg txv,
 input dc,drst,output [3:0] rx_pending,input [3:0] rx_ack,
 output [63:0] rx_lengths,input [12:0] rx_addr,output [7:0] rx_data,
 input tx_we,input [10:0] tx_addr,input [7:0] tx_data,
 input tx_req,input [15:0] tx_length,output reg tx_ack,
 output reg [31:0] crc_errors,rx_overruns,
 output reg [63:0] rx_stats,output [3:0] diagnostic_publication);
 reg snap_req,snap_ack;reg [63:0] snap_payload;reg [1:0] snap_r,snap_a;
 always @(posedge nc or negedge nrst) if(!nrst) begin snap_r<=0;snap_ack<=0;snap_payload<=0;end
 else begin snap_r<={snap_r[0],snap_req};if(snap_r[1]!=snap_ack) begin
  snap_payload<={crc_errors,rx_overruns};snap_ack<=snap_r[1];end end
 always @(posedge dc or negedge drst) if(!drst) begin snap_a<=0;snap_req<=0;rx_stats<=0;end
 else begin snap_a<={snap_a[0],snap_ack};if(snap_req==snap_a[1]) begin
  rx_stats<=snap_payload;snap_req<=~snap_req;end end
 function [31:0] crc_byte(input [31:0] c,input [7:0] d);
 integer j;reg [31:0] v;begin v=c;for(j=0;j<8;j=j+1)
 v=(v[0]^d[j]) ? (v>>1)^32'hedb88320 : v>>1;crc_byte=v;end endfunction
 reg [3:0] request;reg [3:0] ack1,ack2;reg [63:0] lengths;
 assign diagnostic_publication=request;
 reg [3:0] req1,req2;reg [63:0] len1,len2;
 always @(posedge dc or negedge drst) if(!drst) begin req1<=0;req2<=0;len1<=0;len2<=0;end
 else begin req1<=request;req2<=req1;len1<=lengths;len2<=len1;end
 assign rx_pending=req2^rx_ack;assign rx_lengths=len2;
 reg [1:0] slot;reg [10:0] count;reg [31:0] crc;reg active,drop,err,was_rx;
 wire rwe=rxv && active && !drop && count<2048;
 m3_byte_ram #(.BANKS(4),.AW(13)) rxram(.wc(nc),.we(rwe),.wa({slot,count}),.wd(rxd),.rc(dc),.ra(rx_addr),.rd(rx_data));
 always @(posedge nc or negedge nrst) begin
 if(!nrst) begin request<=0;lengths<=0;ack1<=0;ack2<=0;slot<=0;count<=0;crc<=~0;
 active<=0;drop<=0;err<=0;was_rx<=0;crc_errors<=0;rx_overruns<=0;end
 else begin
 ack1<=rx_ack;ack2<=ack1;was_rx<=rxv;
 if(rxv) begin
  if(!active) begin
   if(rxd==8'hd5) begin active<=1;count<=0;crc<=~0;err<=rxe;drop<=request[slot]!=ack2[slot];
    if(request[slot]!=ack2[slot]) rx_overruns<=rx_overruns+1'b1;end
  end else begin count<=count+1'b1;crc<=crc_byte(crc,rxd);err<=err|rxe;
   if(count==2047) drop<=1;end
 end
 if(!rxv && was_rx && active) begin
  active<=0;
  if(!drop && !err && count>=64 && crc==32'hdebb20e3) begin
   lengths[slot*16+:16]<=count-4;request[slot]<=~request[slot];slot<=slot+1'b1;
  end else if(!drop) crc_errors<=crc_errors+1'b1;
 end
 end end
 reg treq1,treq2;reg [15:0] tl1,tl2,len;
 reg [2:0] ts;reg [10:0] ti,tra;reg [4:0] pre,ifg;reg [31:0] tc;
 wire [7:0] tq;
 m3_byte_ram txram(.wc(dc),.we(tx_we),.wa(tx_addr),.wd(tx_data),.rc(nc),.ra(tra),.rd(tq));
 // Read pointer is one ahead of synchronous RAM output during streaming.
 always @(posedge nc or negedge nrst) begin
 if(!nrst) begin treq1<=0;treq2<=0;tl1<=0;tl2<=0;tx_ack<=0;len<=0;ts<=0;ti<=0;tra<=0;
 txv<=0;txd<=0;pre<=0;ifg<=0;tc<=~0;end
 else begin
 treq1<=tx_req;treq2<=treq1;tl1<=tx_length;tl2<=tl1;
 case(ts)
 0:begin txv<=0;tra<=0;if(treq2!=tx_ack) begin len<=tl2;pre<=0;ts<=1;tc<=~0;end end
 1:begin txv<=1;txd<=pre==7 ? 8'hd5 : 8'h55;
   if(pre==7) begin ts<=2;ti<=0;tra<=1;end else pre<=pre+1'b1;end
 2:begin txd<=ti<len ? tq : 0;txv<=1;tc<=crc_byte(tc,ti<len ? tq : 8'd0);
   ti<=ti+1'b1;tra<=tra+1'b1;
   if(ti==((len<60 ? 60 : len)-1)) begin ts<=3;pre<=0;end end
 3:begin txd<=~tc[7:0];tc<=tc>>8;txv<=1;
   if(pre==3) begin ts<=4;ifg<=0;end else pre<=pre+1'b1;end
 4:begin txv<=0;ifg<=ifg+1'b1;if(ifg==12) begin tx_ack<=treq2;ts<=0;end end
 endcase
 end end
endmodule
