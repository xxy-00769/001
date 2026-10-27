`timescale 1ns/1ps
// Explicit clock insertion model distinguishes local pin sampling from the
// fabric clock. The actual ISERDES/OSERDES primitive models are used.
module GTP_CLKBUFG(input CLKIN,output reg CLKOUT);always @(CLKIN) CLKOUT<=#5.7 CLKIN;endmodule
module GTP_IOCLKBUF #(parameter GATE_EN="FALSE")(input CLKIN,DI,output reg CLKOUT);always @(CLKIN) CLKOUT<=#1.6 CLKIN;endmodule
module m36_rgmii_tb;
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 reg source_clk=0;always #4 source_clk=~source_clk;
 wire rxc;assign #2 rxc=source_clk;
 reg rst=0,dv=0;reg [7:0] byte_in=0;reg [3:0] pins=0;reg ctl=0;
 always @(posedge source_clk) begin pins=byte_in[3:0];ctl=dv;end
 always @(negedge source_clk) begin pins=byte_in[7:4];ctl=dv;end
 wire nc,rv,re;wire [7:0] data;
 m36_rgmii_interface u(.rst(rst),.rst90(rst),.rgmii_rxc_phase_d(nc),.rgmii_clk(nc),.rgmii_clk_90p(nc),
 .mac_tx_data_valid(1'b0),.mac_tx_data(8'd0),.mac_rx_error(re),.mac_rx_data_valid(rv),.mac_rx_data(data),
 .rgmii_rxc(rxc),.rgmii_rx_ctl(ctl),.rgmii_rxd(pins),.rgmii_txc(),.rgmii_tx_ctl(),.rgmii_txd());
 function [7:0] pattern(input integer n);pattern=(n*37)^(n>>4)^8'ha7;endfunction
 integer received=0,sent=0;
 always @(negedge nc) if(!rst && rv) begin
  if(re || data!==pattern(received)) $fatal(1,"RGMII byte %0d got=%h want=%h error=%b",received,data,pattern(received),re);
  received++;
 end
 initial begin
  #1;rst=1;#100;rst=0;repeat(30) @(negedge source_clk);
  for(integer k=0;k<4096;k++) begin
   #1;byte_in=pattern(k);dv=1;sent++;
   @(negedge source_clk);
  end
  #1;dv=0;repeat(20) @(negedge source_clk);
  if(received!=sent) $fatal(1,"RGMII first/last dropped %0d/%0d",received,sent);
  $display("M36_RGMII_PASS bytes=%0d pin_skew=2ns IO_insertion=1.6ns fabric_insertion=5.7ns pair_buffer_wrap=256",received);$finish;
 end
 initial begin #100000;$fatal(1,"RGMII timeout");end
endmodule
