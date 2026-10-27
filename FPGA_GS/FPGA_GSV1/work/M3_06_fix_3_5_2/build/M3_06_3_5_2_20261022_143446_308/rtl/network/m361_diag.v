`timescale 1ns/1ps
// Passive status channel. Neither state nor serial output feeds the MAC/PHY.
// Bundled-data request/ack mailboxes hold domain snapshots until acknowledged.
module m361_diag(input sc,nc,dc,rst_n,input [127:0] phy,
 input phy_rstn,phy_ready,mac_ready,core_ready,raw_ctl,rxv,txv,input [7:0] txd,
 input [3:0] published,input [31:0] crc_errors,overruns,
 input [31:0] packets,bad,accepted,session,uploads,aborts,
 input online,tx_req,tx_ack,output uart_tx);
 reg [31:0] raw_frames,bridge_frames,valid_frames,tx_frames,epochs,rx_bytes;
 // RX_CTL is a packet envelope (minimum high 512ns, IFG 96ns at 1Gbps).
 // Observe it asynchronously in the 50MHz domain; do not sample pad data
 // with the late fabric 125MHz clock used by the byte consumer.
 reg [2:0] raw_sync;reg raw_last;
 always @(posedge sc or negedge rst_n) if(!rst_n) begin raw_sync<=0;raw_last<=0;raw_frames<=0;end
 else begin
  raw_sync<={raw_sync[1:0],raw_ctl};raw_last<=raw_sync[2];
  if(raw_sync[2] && !raw_last) raw_frames<=raw_frames+1'b1;
 end
 reg rx_last,tx_last,ready_last;reg [3:0] pub_last;
 always @(posedge nc or negedge rst_n) if(!rst_n) begin
  bridge_frames<=0;valid_frames<=0;tx_frames<=0;epochs<=0;rx_bytes<=0;
  rx_last<=0;tx_last<=0;ready_last<=0;pub_last<=0;
 end else begin
  rx_last<=rxv;tx_last<=txv;ready_last<=mac_ready;
  if(rxv && !rx_last) bridge_frames<=bridge_frames+1'b1;
  if(txv && !tx_last) tx_frames<=tx_frames+1'b1;
  if(ready_last && !mac_ready) epochs<=epochs+1'b1;
  if(rxv) rx_bytes<=rx_bytes+1'b1;
  pub_last<=mac_ready ? published:4'd0;
  if(mac_ready && published!=pub_last) valid_frames<=valid_frames+1'b1;
 end
 reg [31:0] requests,completions;reg req_last;
 // Count completion in the MAC clock domain, then transfer a held snapshot.
 // Never use asynchronous tx_ack as a combinational increment enable in dc.
 reg ack_last;
 always @(posedge nc or negedge rst_n) if(!rst_n) begin completions<=0;ack_last<=0;end
 else begin
  ack_last<=tx_ack;
  if(mac_ready && tx_ack!=ack_last) completions<=completions+1'b1;
 end
 wire [31:0] completions_dc;
 m361_snapshot completion_snapshot(.sc(nc),.dc(dc),.rst_n(rst_n),.value(completions),.snapshot(completions_dc));
 always @(posedge dc or negedge rst_n) if(!rst_n) begin
  requests<=0;req_last<=0;
 end else begin
  req_last<=tx_req;
  if(core_ready && tx_req!=req_last) requests<=requests+1'b1;
 end
 wire [255:0] nvalue={32'd0,bridge_frames,valid_frames,crc_errors,overruns,tx_frames,epochs,rx_bytes};
 wire [287:0] dvalue={packets,bad,accepted,session,uploads,aborts,requests,completions_dc,
  27'd0,online,core_ready,mac_ready,tx_req,tx_ack};
 wire [255:0] nsnap;wire [287:0] dsnap;
 m361_snapshot #(.W(256)) ns(.sc(nc),.dc(sc),.rst_n(rst_n),.value(nvalue),.snapshot(nsnap));
 m361_snapshot #(.W(288)) ds(.sc(dc),.dc(sc),.rst_n(rst_n),.value(dvalue),.snapshot(dsnap));
 reg [1:0] ready_sync,core_sync,mac_sync;
 always @(posedge sc or negedge rst_n) if(!rst_n) begin ready_sync<=0;core_sync<=0;mac_sync<=0;end
 else begin ready_sync<={ready_sync[0],phy_ready};core_sync<={core_sync[0],core_ready};mac_sync<={mac_sync[0],mac_ready};end
 // Last complete minimum-sized ARP as actually emitted by production MAC,
 // including preamble/SFD, Ethernet padding and FCS. Purely passive: no
 // request/ack/ready/data signal is fed back into the live datapath.
 reg [575:0] tx_shift,last_arp;
 reg [6:0] tx_bytes;
 reg txv_previous;
 always @(posedge nc or negedge rst_n) if(!rst_n) begin
  tx_shift<=0;last_arp<=0;tx_bytes<=0;txv_previous<=0;
 end else begin
  txv_previous<=txv;
  if(txv) begin
   if(!txv_previous) begin tx_shift<={568'd0,txd};tx_bytes<=1;end
   else if(tx_bytes<73) begin
    tx_bytes<=tx_bytes+1'b1;
    if(tx_bytes<72) tx_shift<={tx_shift[567:0],txd};
   end
  end else if(txv_previous && tx_bytes==72 && tx_shift[415:400]==16'h0806)
   last_arp<=tx_shift;
 end
 wire [575:0] arp_snapshot;
 m361_snapshot #(.W(576)) arp_record(.sc(nc),.dc(sc),.rst_n(rst_n),.value(last_arp),.snapshot(arp_snapshot));
 wire [1279:0] values={phy,raw_frames,nsnap[223:0],dsnap,29'd0,phy_rstn,core_sync[1],mac_sync[1],arp_snapshot};
 m361_uart_hex serial(.clk(sc),.rst_n(rst_n),.values(values),.tx(uart_tx));
endmodule

module m361_snapshot #(parameter W=32)(input sc,dc,rst_n,input [W-1:0] value,output reg [W-1:0] snapshot);
 reg req,ack;reg [1:0] r,a;reg [W-1:0] payload;
 always @(posedge sc or negedge rst_n) if(!rst_n) begin r<=0;ack<=0;payload<=0;end
 else begin r<={r[0],req};if(r[1]!=ack) begin payload<=value;ack<=r[1];end end
 always @(posedge dc or negedge rst_n) if(!rst_n) begin req<=0;a<=0;snapshot<=0;end
 else begin a<={a[0],ack};if(req==a[1]) begin snapshot<=payload;req<=~req;end end
endmodule

// 115200 8N1 @ 50MHz. One atomic line/second; 22 status words + 18 words of last ARP TX bytes.
module m361_uart_hex #(parameter TICKS=50000000,BAUD_DIV=434)(
 input clk,rst_n,input [1279:0] values,output tx);
 reg [25:0] timer;reg [1279:0] held;reg [8:0] index;
 reg sending;reg [9:0] shift;reg [3:0] bits_left;reg [8:0] baud;
 reg [7:0] character;reg [3:0] nibble;
 assign tx=bits_left!=0 ? shift[0]:1'b1;
 always @* begin
  nibble=0;character=8'h20;
  case(index)
   0:character="N";1:character="2";2:character=" ";3:character="3";
   4:character="5";5:character="2";6:character=" ";
   367:character=13;368:character=10;
   default:if(index>=7 && index<367 && (index-7)%9!=8) begin
    nibble=held[1279-(((index-7)/9)*8+(index-7)%9)*4-:4];
    character=nibble<10 ? 8'h30+nibble:8'h41+nibble-10;
   end
  endcase
 end
 always @(posedge clk or negedge rst_n) if(!rst_n) begin
  timer<=0;held<=0;index<=0;sending<=0;shift<=10'h3ff;bits_left<=0;baud<=0;
 end else begin
  if(timer==TICKS-1) begin timer<=0;if(!sending) begin held<=values;sending<=1;index<=0;end end
  else timer<=timer+1'b1;
  if(bits_left!=0) begin
   if(baud==BAUD_DIV-1) begin baud<=0;shift<={1'b1,shift[9:1]};bits_left<=bits_left-1'b1;end
   else baud<=baud+1'b1;
  end else if(sending) begin
   shift<={1'b1,character,1'b0};bits_left<=10;baud<=0;
   if(index==368) sending<=0;else index<=index+1'b1;
  end
 end
endmodule
