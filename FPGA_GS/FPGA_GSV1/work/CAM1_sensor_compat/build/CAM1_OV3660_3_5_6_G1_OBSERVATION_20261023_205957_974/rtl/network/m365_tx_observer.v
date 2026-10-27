`timescale 1ns/1ps
// Passive checker at the production GMII boundary register, immediately before
// E1 ODDR serialization. No output feeds back to ready, clocks or packet logic.
module m365_gmii_crc(input clk,rst_n,valid,input [7:0] data,
 output reg [31:0] frames,bad_frames,last_bad_id,last_bad_residue,
 output reg [15:0] last_bad_length);
 function [31:0] next_crc(input [31:0] value,input [7:0] octet);
  reg [31:0] c;integer i;
  begin c=value;for(i=0;i<8;i=i+1)
   c=(c[0]^octet[i]) ? ((c>>1)^32'hedb88320):(c>>1);
   next_crc=c;
  end
 endfunction
 reg previous,header_bad;
 reg [15:0] count;
 reg [31:0] residue,identity;
 always @(posedge clk or negedge rst_n) if(!rst_n) begin
  previous<=0;header_bad<=0;count<=0;residue<=32'hffffffff;identity<=0;
  frames<=0;bad_frames<=0;last_bad_id<=0;last_bad_residue<=0;last_bad_length<=0;
 end else begin
  previous<=valid;
  if(valid) begin
   if(!previous) begin
    count<=1;residue<=32'hffffffff;header_bad<=data!=8'h55;identity<=0;
   end else begin
    if(count!=16'hffff) count<=count+1'b1;
    if(count<7 && data!=8'h55) header_bad<=1;
    if(count==7 && data!=8'hd5) header_bad<=1;
    if(count>=8) residue<=next_crc(residue,data);
    if(count>=62 && count<=65) identity<={identity[23:0],data};
   end
  end else if(previous) begin
   frames<=frames+1'b1;
   if(header_bad || count<72 || count>1526 || residue!=32'hdebb20e3) begin
    bad_frames<=bad_frames+1'b1;
    last_bad_id<=identity;last_bad_residue<=residue;last_bad_length<=count;
   end
  end
 end
endmodule

module m365_tx_observer(input sc,nc,rst_n,input [127:0] phy,
 input pll_lock,phy_ready,txv,input [7:0] txd,
 input [383:0] camera_diagnostics,output uart_tx);
 wire [31:0] frames,bad,last_id,last_residue;
 wire [15:0] last_length;
 m365_gmii_crc crc_monitor(.clk(nc),.rst_n(rst_n),.valid(txv),.data(txd),
  .frames(frames),.bad_frames(bad),.last_bad_id(last_id),
  .last_bad_residue(last_residue),.last_bad_length(last_length));
 wire [159:0] nsnap;
 m361_snapshot #(.W(160)) ns(.sc(nc),.dc(sc),.rst_n(rst_n),
  .value({frames,bad,last_id,last_residue,16'd0,last_length}),.snapshot(nsnap));
 reg [2:0] lock_sync,ready_sync;
 reg [31:0] lock_falls,ready_falls;
 always @(posedge sc or negedge rst_n) if(!rst_n) begin
  lock_sync<=0;ready_sync<=0;lock_falls<=0;ready_falls<=0;
 end else begin
  lock_sync<={lock_sync[1:0],pll_lock};ready_sync<={ready_sync[1:0],phy_ready};
  if(lock_sync[2] && !lock_sync[1]) lock_falls<=lock_falls+1'b1;
  if(ready_sync[2] && !ready_sync[1]) ready_falls<=ready_falls+1'b1;
 end
 // Existing N2 serial encoding: 40 words, 115200 8N1, one atomic line/sec.
 // W0..3 PHY; W4 total frames; W5 bad GMII FCS/framing; W6 last bad ID;
 // W7 last residue; W8 last length; W9 PLL falls; W10 ready falls;
 // W11 status (bit1 PLL, bit0 ready); W12..15 passive camera status;
 // W16..23 existing CAM1 geometry snapshot, W24..39 reserved zero.
 // Camera data is in sc and cannot affect GMII/PHY.
 m361_uart_hex #(.REVISION_ASCII("O")) serial(.clk(sc),.rst_n(rst_n),
  .values({phy,nsnap,lock_falls,ready_falls,30'd0,lock_sync[2],ready_sync[2],camera_diagnostics,512'd0}),
  .tx(uart_tx));
endmodule
