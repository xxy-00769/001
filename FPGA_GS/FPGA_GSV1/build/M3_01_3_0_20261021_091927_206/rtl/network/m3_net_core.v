`timescale 1ns/1ps
// One IPv4/UDP endpoint for video/control. Ethernet frames have already passed
// FCS before this bounded parser sees them. No speculative DDR writes.
module m3_net_core #(
 parameter LOCAL_MAC=48'h020047535631,LOCAL_IP=32'hc0a83202,HOST_IP=32'hc0a83201,
 parameter PORT=16'd50000,MS_CYCLES=100000)(
 input clk,rst_n,input [3:0] rx_pending,output reg [3:0] rx_ack,
 input [63:0] rx_lengths,output reg [12:0] rx_addr,input [7:0] rx_data,
 output reg tx_we,output reg [10:0] tx_addr,output reg [7:0] tx_data,
 output reg tx_req,output reg [15:0] tx_length,input tx_ack,
 output reg right_begin,input right_begin_ack,right_bank,output reg right_publish,
 output reg [31:0] right_id,output right_healthy,
 output reg [27:0] awaddr,output [3:0] awlen,output awvalid,input awready,
 output [255:0] wdata,output [31:0] wstrb,input wready,wlast,
 input key_event,input [3:0] key_code,input [31:0] latest_front_id,
 output reg [2:0] feedback,output online,output tick_ms,output reg [7:0] upload_fps,
 input fragment_ready,output reg fragment_taken,input [31:0] front_id,front_time,front_offset,
 input [15:0] front_index,output [8:0] front_word_addr,input [31:0] front_word_data,
 output reg [31:0] session,rx_packets,bad_packets,right_frames,right_drops,control_events);
 function [7:0] hb(input [719:0] a,input integer n);begin hb=a[719-n*8-:8];end endfunction
 function [31:0] hw(input [719:0] a,input integer n);begin hw={hb(a,n),hb(a,n+1),hb(a,n+2),hb(a,n+3)};end endfunction
 function [15:0] hh(input [719:0] a,input integer n);begin hh={hb(a,n),hb(a,n+1)};end endfunction
 function [15:0] fold(input [31:0] v);reg [31:0] a;begin a=v[15:0]+v[31:16];a=a[15:0]+a[31:16];fold=a[15:0];end endfunction
 reg [31:0] ms,ms_count;assign tick_ms=ms_count==MS_CYCLES-1;
 reg [31:0] last_seen,right_last,right_session;
 reg [31:0] seen_age,right_age,event_age,assembly_age,event_tx_age,heart_age;
 reg live;
 assign online=live;
 assign right_healthy=online && right_session==session && right_age<1000 && right_frames!=0;
 always @(posedge clk or negedge rst_n) if(!rst_n) begin ms<=0;ms_count<=0;end
 else if(tick_ms) begin ms_count<=0;ms<=ms+1'b1;end else ms_count<=ms_count+1'b1;
 reg [1:0] slot;reg [15:0] length,pos;reg [719:0] head;
 reg [31:0] ipsum,udpsum;reg [7:0] prev;
 reg [4:0] rs;localparam R_IDLE=0,R_WAIT=1,R_SCAN=2,R_CHECK=3,R_PARSE=4,R_BEGIN=5,
 R_PAYWAIT=6,R_PAY=7,R_AW=8,R_W=9,R_FINISH=10,R_DROP=11,R_COMMIT=12;
 reg [255:0] beat;reg [4:0] bytepos;reg [15:0] payload_pos;
 reg assembly;reg [31:0] assembling_id,next_offset,assembly_time;reg [15:0] next_index;
 wire [31:0] p_session=hw(head,50),p_frame=hw(head,54),p_offset=hw(head,66);
 wire [15:0] p_len=hh(head,70),p_index=hh(head,72);
 wire [7:0] p_type=hb(head,47);
 assign awlen=0;assign awvalid=rs==R_AW;assign wdata=beat;assign wstrb=32'hffffffff;
 reg arp_pending;reg [47:0] arp_mac,peer_mac;reg [31:0] arp_ip;
 reg event_pending,event_acknowledged,result_ack_pending,hello_pending;
 reg [31:0] event_id,event_frame,event_time,last_event_tx,last_heart,result_seq;
 reg [15:0] result_ttl;reg [31:0] last_right_id;reg have_right_id;
 // Isolate subtraction from expiry / priority muxes. Two core cycles (20ns)
 // of observation latency versus millisecond deadlines, with no clock waiver.
 always @(posedge clk or negedge rst_n) if(!rst_n) begin
  seen_age<=2000;right_age<=1000;event_age<=2000;assembly_age<=500;
  event_tx_age<=0;heart_age<=0;live<=0;
 end else begin
  seen_age<=ms-last_seen;right_age<=ms-right_last;event_age<=ms-event_time;
  assembly_age<=ms-assembly_time;event_tx_age<=ms-last_event_tx;heart_age<=ms-last_heart;
  live<=session!=0 && seen_age<2000;
 end
 reg [3:0] action;reg [31:0] ack_event,ack_seq;reg [7:0] ack_code;
 // Syntax avoiding expression bit slices for Verilog-2001 tools.
 wire [15:0] ip_flags=hh(head,20);
 reg [3:0] ts;reg [15:0] ti,tlen;reg [7:0] tx_kind;
 reg [719:0] txhead;reg [31:0] out_session,out_frame,out_time,out_offset,out_event,out_seq;
 reg [15:0] out_index;reg [7:0] out_code,out_reason;
 reg tx_done;reg [1:0] ta;reg [15:0] ipid;reg [31:0] sum;
 integer k;
 always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin
 rx_ack<=0;rx_addr<=0;slot<=0;length<=0;pos<=0;head<=0;ipsum<=0;udpsum<=0;prev<=0;rs<=0;
 beat<=0;bytepos<=0;payload_pos<=0;right_begin<=0;right_publish<=0;right_id<=0;
 assembly<=0;assembling_id<=0;next_offset<=0;next_index<=0;assembly_time<=0;
 session<=0;last_seen<=0;right_last<=32'hffff0000;feedback<=0;upload_fps<=5;
 rx_packets<=0;bad_packets<=0;right_frames<=0;right_drops<=0;control_events<=0;
 awaddr<=0;arp_pending<=0;arp_mac<=0;arp_ip<=0;peer_mac<=0;
 event_pending<=0;event_acknowledged<=0;result_ack_pending<=0;hello_pending<=0;
 event_id<=0;event_frame<=0;event_time<=0;last_event_tx<=0;last_heart<=0;result_seq<=0;
 result_ttl<=0;right_session<=0;last_right_id<=0;have_right_id<=0;
 action<=0;ack_event<=0;ack_seq<=0;ack_code<=0;
 end else begin
 right_publish<=0;right_begin<=0;
 if(!online) feedback<=0;
 if(event_id!=0 && event_age>=(result_ttl==0 ? 2000:result_ttl)) feedback<=0;
 if(assembly && assembly_age>=500) begin assembly<=0;right_drops<=right_drops+1'b1;end
 if(key_event && key_code>=1 && key_code<=4) begin
  event_id<=event_id+1'b1;event_frame<=latest_front_id;event_time<=ms;action<=key_code;
  event_pending<=1;event_acknowledged<=0;feedback<=0;result_seq<=0;result_ttl<=0;control_events<=control_events+1'b1;
 end
 // TX scheduler consumes flags only after a complete frame was copied.
 if(tx_done) begin
  case(tx_kind)
   0:arp_pending<=0;
   2:hello_pending<=0;
   3:last_heart<=ms;
   4:begin event_pending<=0;last_event_tx<=ms;end
   7:result_ack_pending<=0;
  endcase
 end
 case(rs)
 R_IDLE:begin
  if(rx_pending!=0) begin
   if(rx_pending[0]) slot<=0;else if(rx_pending[1]) slot<=1;else if(rx_pending[2]) slot<=2;else slot<=3;
   pos<=0;head<=0;ipsum<=0;udpsum<=0;rs<=R_WAIT;
   if(rx_pending[0]) begin rx_addr<=0;length<=rx_lengths[0+:16];end
   else if(rx_pending[1]) begin rx_addr<=2048;length<=rx_lengths[16+:16];end
   else if(rx_pending[2]) begin rx_addr<=4096;length<=rx_lengths[32+:16];end
   else begin rx_addr<=6144;length<=rx_lengths[48+:16];end
  end
 end
 R_WAIT:rs<=R_SCAN;
 R_SCAN:begin
  if(pos<90) head[719-pos*8-:8]<=rx_data;
  if(pos[0]) begin
   if(pos>=15 && pos<34) ipsum<=ipsum+{prev,rx_data};
   if(pos>=35) udpsum<=udpsum+{prev,rx_data};
  end
  prev<=rx_data;
  if(pos+1>=length) begin
   if(!pos[0] && pos>=34) udpsum<=udpsum+{rx_data,8'd0};
   rs<=R_CHECK;
  end else begin pos<=pos+1'b1;rx_addr<={slot,11'd0}+pos+1'b1;rs<=R_WAIT;end
 end
 R_CHECK:begin
  rx_packets<=rx_packets+1'b1;
  if(length>=42 && {hb(head,12),hb(head,13)}==16'h0806 && hh(head,14)==1 && hh(head,16)==16'h0800 &&
   hh(head,20)==1 && hw(head,38)==LOCAL_IP && hw(head,28)==HOST_IP) begin
   arp_mac<={hw(head,22),hh(head,26)};arp_ip<=hw(head,28);arp_pending<=1;rs<=R_FINISH;
  end else if(length>=90 && {hw(head,0),hh(head,4)}==LOCAL_MAC && hh(head,12)==16'h0800 && hb(head,14)==8'h45 && hb(head,23)==17 &&
   (ip_flags & 16'h3fff)==0 && fold(ipsum)==16'hffff && hw(head,26)==HOST_IP && hw(head,30)==LOCAL_IP &&
   hh(head,36)==PORT && hh(head,34)==PORT && hh(head,16)+14==length && hh(head,38)+34==length &&
   (hh(head,40)==0 || fold(udpsum+hh(head,26)+hh(head,28)+hh(head,30)+hh(head,32)+17+hh(head,38))==16'hffff) &&
   hw(head,42)==32'h47535633 && hb(head,46)==1 && hh(head,70)+90==length) begin rs<=R_PARSE;end
  else begin bad_packets<=bad_packets+1'b1;rs<=R_FINISH;end
 end
 R_PARSE:begin
  rs<=R_FINISH;
  if(p_type==1 && p_session!=0 && (!online || p_session==session)) begin
   peer_mac<={hw(head,6),hh(head,10)};last_seen<=ms;hello_pending<=1;
   upload_fps<=hb(head,89)>30 ? 30 : hb(head,89);
   if(p_session!=session) begin session<=p_session;assembly<=0;event_pending<=0;
    event_id<=0;feedback<=0;event_acknowledged<=0;result_seq<=0;have_right_id<=0;end
  end else if(online && p_session==session) begin
   if(p_type==3) last_seen<=ms;
   else if(p_type==5 && hw(head,78)==event_id) event_acknowledged<=1;
   else if(p_type==6) begin
    ack_event<=hw(head,78);ack_seq<=hw(head,82);ack_code<=0;result_ack_pending<=1;
    if(hw(head,78)==event_id && p_frame==event_frame && event_id!=0 &&
     hw(head,82)>result_seq && hh(head,86)>0 && hh(head,86)<=2000 &&
     event_age<hh(head,86) && hb(head,88)<=2 && hb(head,89)<=2 && !key_event) begin
      result_seq<=hw(head,82);result_ttl<=hh(head,86);ack_code<=1;
      feedback<=hb(head,89)==1 ? 3 : hb(head,89)==2 ? 4 : (hb(head,88)&7);
    end
   end else if(p_type==16 && hb(head,48)==3 && hb(head,49)==1 && hh(head,62)==1280 && hh(head,64)==720 &&
    p_len==1280 && hh(head,74)==1440 && p_index<1440 && p_offset==p_index*1280) begin
    if(p_index==0 && (!assembly || p_frame!=assembling_id) && (!have_right_id || $signed(p_frame-last_right_id)>0)) begin
     if(assembly) right_drops<=right_drops+1'b1;
     assembling_id<=p_frame;last_right_id<=p_frame;have_right_id<=1;assembly_time<=ms;next_offset<=0;next_index<=0;assembly<=1;right_id<=p_frame;
     right_begin<=1;rs<=R_BEGIN;
    end else if(assembly && p_frame==assembling_id && p_index==next_index && p_offset==next_offset) begin
     payload_pos<=0;bytepos<=0;rx_addr<={slot,11'd0}+90;rs<=R_PAYWAIT;
    end else if(!(assembly && p_frame==assembling_id && p_index<next_index)) begin
     assembly<=0;right_drops<=right_drops+1'b1;
    end
   end else if(p_type==16) begin bad_packets<=bad_packets+1'b1;assembly<=0;end
  end else if(p_type!=1) bad_packets<=bad_packets+1'b1;
 end
 R_BEGIN:begin
  right_begin<=1;
  if(right_begin_ack) begin right_begin<=0;payload_pos<=0;bytepos<=0;
   rx_addr<={slot,11'd0}+90;rs<=R_PAYWAIT;end
 end
 R_PAYWAIT:rs<=R_PAY;
 R_PAY:begin
  beat[bytepos*8+:8]<=rx_data;
  if(bytepos==31) begin
   awaddr<={3'd0,2'd3,right_bank,22'd0}+(p_offset>>2)+(payload_pos>>2)-7;
   rs<=R_AW;
  end else begin bytepos<=bytepos+1'b1;payload_pos<=payload_pos+1'b1;rx_addr<=rx_addr+1'b1;rs<=R_PAYWAIT;end
 end
 R_AW:if(awready) begin if(wready && wlast) rs<=R_COMMIT;else rs<=R_W;end
 R_W:if(wready && wlast) rs<=R_COMMIT;
 R_COMMIT:begin
  if(payload_pos==1279) begin
   next_offset<=p_offset+1280;next_index<=p_index+1'b1;
   if(p_index==1439 && assembly) begin right_publish<=1;right_frames<=right_frames+1'b1;right_last<=ms;right_session<=session;assembly<=0;end
   rs<=R_FINISH;
  end else begin payload_pos<=payload_pos+1'b1;bytepos<=0;rx_addr<=rx_addr+1'b1;rs<=R_PAYWAIT;end
 end
 R_FINISH:begin rx_ack[slot]<=~rx_ack[slot];rs<=R_IDLE;end
 endcase
 end end

 // TX is bounded to one Ethernet packet, with control priority at packet
 // boundaries. Header fields are snapshotted; no mid-packet session mutation.
 wire fragment_choice=fragment_ready && online;
 assign front_word_addr=(ti>=90 ? ti-90 : 0)>>2;
 function [7:0] ipv4_byte(input integer n);
 reg [15:0] total,check,ul;reg [31:0] ss;begin
 total=tlen-14;ul=tlen-34;
 ss=16'h4500+total+ipid+16'h4000+16'h4011+LOCAL_IP[31:16]+LOCAL_IP[15:0]+HOST_IP[31:16]+HOST_IP[15:0];check=~fold(ss);
 ipv4_byte=0;
 case(n)
 0:ipv4_byte=8'h45;2:ipv4_byte=total[15:8];3:ipv4_byte=total[7:0];4:ipv4_byte=ipid[15:8];5:ipv4_byte=ipid[7:0];
 6:ipv4_byte=8'h40;8:ipv4_byte=64;9:ipv4_byte=17;10:ipv4_byte=check[15:8];11:ipv4_byte=check[7:0];
 12,13,14,15:ipv4_byte=LOCAL_IP>>(8*(15-n));16,17,18,19:ipv4_byte=HOST_IP>>(8*(19-n));
 20,22:ipv4_byte=PORT[15:8];21,23:ipv4_byte=PORT[7:0];24:ipv4_byte=ul[15:8];25:ipv4_byte=ul[7:0];
 endcase end endfunction
 function [7:0] app_byte(input integer n);begin app_byte=0;
 case(n)
 0:app_byte=8'h47;1:app_byte=8'h53;2:app_byte=8'h56;3:app_byte=8'h33;4:app_byte=1;
 5:app_byte=tx_kind;6:app_byte=0;7:app_byte=1;
 8,9,10,11:app_byte=out_session>>(8*(11-n));12,13,14,15:app_byte=out_frame>>(8*(15-n));
 16,17,18,19:app_byte=out_time>>(8*(19-n));20:app_byte=5;21:app_byte=0;22:app_byte=2;23:app_byte=8'hd0;
 24,25,26,27:app_byte=out_offset>>(8*(27-n));
 28:app_byte=tx_kind==17 ? 5:0;29:app_byte=0;
 30:app_byte=out_index[15:8];31:app_byte=out_index[7:0];
 32:app_byte=tx_kind==17 ? 5:0;33:app_byte=tx_kind==17 ? 8'ha0:0;
 36,37,38,39:app_byte=out_event>>(8*(39-n));40,41,42,43:app_byte=out_seq>>(8*(43-n));
 44:app_byte=7;45:app_byte=8'hd0;46:app_byte=out_code;47:app_byte=out_reason;
 endcase end endfunction
 function [7:0] wire_byte(input integer n);begin wire_byte=0;
 if(n<6) wire_byte=(tx_kind==0 ? arp_mac : peer_mac)>>(8*(5-n));
 else if(n<12) wire_byte=LOCAL_MAC>>(8*(11-n));
 else if(tx_kind==0) begin
  case(n)
  12:wire_byte=8'h08;13:wire_byte=6;15:wire_byte=1;16:wire_byte=8'h08;
  18:wire_byte=6;19:wire_byte=4;21:wire_byte=2;
  22,23,24,25,26,27:wire_byte=LOCAL_MAC>>(8*(27-n));
  28,29,30,31:wire_byte=LOCAL_IP>>(8*(31-n));
  32,33,34,35,36,37:wire_byte=arp_mac>>(8*(37-n));
  38,39,40,41:wire_byte=arp_ip>>(8*(41-n));
  endcase
 end else if(n==12) wire_byte=8'h08;
 else if(n<42 && n>=14) wire_byte=ipv4_byte(n-14);
 else if(n>=42 && n<90) wire_byte=app_byte(n-42);
 end endfunction
 always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin ts<=0;ti<=0;tlen<=0;tx_kind<=0;txhead<=0;
 tx_we<=0;tx_addr<=0;tx_data<=0;tx_req<=0;tx_length<=0;ta<=0;ipid<=0;
 out_session<=0;out_frame<=0;out_time<=0;out_offset<=0;out_event<=0;out_seq<=0;out_index<=0;
 out_code<=0;out_reason<=0;fragment_taken<=0;tx_done<=0;sum<=0;end
 else begin
 ta<={ta[0],tx_ack};tx_we<=0;fragment_taken<=0;tx_done<=0;
 case(ts)
 0:if(tx_req==ta[1]) begin
  if(arp_pending || hello_pending || result_ack_pending ||
   (online && event_id!=0 && !event_acknowledged && event_age<2000 && (event_pending || event_tx_age>=200)) ||
   (online && heart_age>=500) || fragment_choice) begin
   tx_kind<=arp_pending ? 0 : hello_pending ? 2 : result_ack_pending ? 7 :
    (event_id!=0 && !event_acknowledged && event_age<2000 && (event_pending || event_tx_age>=200)) ? 4 :
    heart_age>=500 ? 3 : 17;
   tlen<=arp_pending ? 42 : (!hello_pending && !result_ack_pending &&
    !(event_id!=0 && !event_acknowledged && event_age<2000 && (event_pending || event_tx_age>=200)) &&
    !(online && heart_age>=500) && fragment_choice) ? 1370 : 90;
   out_session<=session;out_frame<=(!arp_pending && !hello_pending && !result_ack_pending && !(event_id!=0 && !event_acknowledged && event_age<2000 && (event_pending || event_tx_age>=200)) && !(online && heart_age>=500)) ? front_id : event_frame;
   out_time<=fragment_choice ? front_time : event_time;out_offset<=fragment_choice ? front_offset : 0;
   out_index<=fragment_choice ? front_index : 0;out_event<=result_ack_pending ? ack_event : event_id;
   out_seq<=result_ack_pending ? ack_seq : 0;out_code<=result_ack_pending ? ack_code : {4'd0,action};out_reason<=0;
   ti<=0;ipid<=ipid+1'b1;ts<=1;
  end
 end
 1:ts<=2; // staging word address settles before byte fetch
 2:begin tx_addr<=ti;tx_we<=1;
   tx_data<=ti<90 ? wire_byte(ti) : (front_word_data>>(8*((ti-90)%4)));
   if(ti+1>=tlen) ts<=3;else begin ti<=ti+1'b1;ts<=1;end
 end
 3:begin tx_length<=tlen;tx_req<=~tx_req;tx_done<=1;
   if(tx_kind==17) fragment_taken<=1;ts<=4;end
 4:if(tx_req==ta[1]) ts<=0;
 endcase
 end end
endmodule
