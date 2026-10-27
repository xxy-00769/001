`timescale 1ns/1ps
// Sustained production MAC/TX RAM -> two-byte bridge -> OSER4 -> pins.
// Same payload remains in RAM to remove producer idle time between requests.
module m363_burst_tb;
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 reg rxc=0,dc=0,run=1;
 always #4 rxc=~rxc;always #5 dc=~dc;
 wire nc,txc,ctl;wire [3:0] pins;wire [7:0] gmii;wire valid,ack;
 reg we=0,req=0;reg [10:0] addr=0;reg [7:0] data=0;reg [15:0] length=42;
 m36_rgmii_interface io(.rst(!run),.rst90(!run),.rgmii_rxc_phase_d(1'b0),
 .rgmii_clk(nc),.rgmii_clk_90p(1'b0),.mac_tx_data_valid(valid),.mac_tx_data(gmii),
 .rgmii_rxc(rxc),.rgmii_rx_ctl(1'b0),.rgmii_rxd(4'd0),
 .rgmii_txc(txc),.rgmii_tx_ctl(ctl),.rgmii_txd(pins));
 m3_mac mac(.nc(nc),.nrst(run),.rxd(8'd0),.rxv(1'b0),.rxe(1'b0),
 .txd(gmii),.txv(valid),.dc(dc),.drst(run),.rx_ack(4'd0),.rx_addr(13'd0),
 .tx_we(we),.tx_addr(addr),.tx_data(data),.tx_req(req),.tx_length(length),.tx_ack(ack));
 function [7:0] pattern(input integer j);pattern=(j*73)^(j>>3)^8'ha7;endfunction
 function [31:0] crc(input [31:0] v,input [7:0] d);reg [31:0] x;begin
  x=v;for(integer j=0;j<8;j++) x=(x[0]^d[j]) ? (x>>1)^32'hedb88320:x>>1;crc=x;end endfunction
 wire sample_clock;assign #2.038 sample_clock=txc;
 wire [3:0] observed_pins;assign #0.036 observed_pins=pins;
 wire observed_ctl;assign #0.009 observed_ctl=ctl;
 integer frames=0,count=0,ifg=0,min_ifg=999999,body_size,body_len,byte_count=0;
 reg was=0,previous=0;reg [3:0] low;reg [7:0] byte_out;reg [31:0] fcs;
 always @(posedge sample_clock) begin low=observed_pins;was=observed_ctl;end
 always @(negedge sample_clock) begin
  if(was) begin
   if(!observed_ctl) $fatal(1,"burst CTL edge mismatch");
   byte_out={observed_pins,low};
   if(count==0) begin
    if(previous) begin if(ifg<12) $fatal(1,"burst IFG %0d",ifg);if(ifg<min_ifg) min_ifg=ifg;end
    fcs=32'hffffffff;body_len=frames==0 ? 42:(frames<65 ? 90:1370);body_size=body_len<60 ? 60:body_len;
   end
   if(count<7 && byte_out!==8'h55) $fatal(1,"burst preamble");
   if(count==7 && byte_out!==8'hd5) $fatal(1,"burst SFD");
   if(count>=8 && count<8+body_size && byte_out!==(count-8<body_len ? pattern(count-8):8'd0))
    $fatal(1,"burst byte frame=%0d index=%0d got=%h",frames,count,byte_out);
   if(count>=8) fcs=crc(fcs,byte_out);
   count++;byte_count++;ifg=0;previous=1;
  end else begin
   if(count!=0) begin
    if(count!=body_size+12 || fcs!==32'hdebb20e3) $fatal(1,"burst end/FCS count=%0d crc=%h",count,fcs);
    frames++;count=0;
   end
   ifg++;
  end
 end
 initial begin
  #1;run=0;#103;run=1;
  for(integer j=0;j<1370;j++) begin @(negedge dc);we=1;addr=j;data=pattern(j);end
  @(negedge dc);we=0;
  for(integer j=0;j<73;j++) begin
   @(negedge dc);length=j==0 ? 42:(j<65 ? 90:1370);req=!req;
   wait(ack==req);
  end
  wait(frames==73);
  if(min_ifg>24) $fatal(1,"burst did not reach consecutive traffic %0d",min_ifg);
  $display("M363_BURST_PASS ARP_size=1 control=64 front_size=8 frames=%0d bytes=%0d min_ifg=%0d",frames,byte_count,min_ifg);$finish;
 end
 initial begin #1000000;$fatal(1,"burst timeout frames=%0d count=%0d req=%b ack=%b state=%d nc=%b serialreset=%b stream=%b",frames,count,req,ack,mac.ts,nc,io.tx_serial_reset,io.tx_streaming);end
endmodule
