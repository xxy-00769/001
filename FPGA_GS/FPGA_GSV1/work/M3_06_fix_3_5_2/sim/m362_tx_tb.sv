`timescale 1ns/1ps
module GTP_CLKBUFG(input CLKIN,output reg CLKOUT);always @(CLKIN) CLKOUT<=#5.7 CLKIN;endmodule
module GTP_IOCLKBUF #(parameter GATE_EN="FALSE")(input CLKIN,DI,output reg CLKOUT);always @(CLKIN) CLKOUT<=#1.6 CLKIN;endmodule
module m362_tx_tb;
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 reg c=0,dc=0,source_clk=0,rst=0;
 always #10 c=~c;always #5 dc=~dc;always #4 source_clk=~source_clk;
 wire rxc;assign #2 rxc=source_clk;
 reg dv=0;reg [7:0] byte_in=0;reg [3:0] pins=0;reg ctl=0;
 always @(posedge source_clk) begin pins=byte_in[3:0];ctl=dv;end
 always @(negedge source_clk) begin pins=byte_in[7:4];ctl=dv;end
 tri1 mdio;wire mdc,txc,txctl,phy_reset;wire [3:0] txpins;
 m3_network #(.ENABLE_VIDEO(0),.PHY_INTERNAL_DELAY(1),.LOCAL_MAC(48'h020047535632),.LOCAL_IP(32'hc0a83c02),.HOST_IP(32'hc0a83c01)) dut(
 .clk(dc),.rst_n(rst),.sys_clk(c),.phy_reset_n(rst),.rgmii_rxc(rxc),.rgmii_rx_ctl(ctl),.rgmii_rxd(pins),
 .rgmii_txc(txc),.rgmii_tx_ctl(txctl),.rgmii_txd(txpins),.phy_rstn(phy_reset),.phy_mdc(mdc),.phy_mdio(mdio),
 .pc(dc),.fs(1'b0),.selected(1'b0),.quarter(1'b0),.request(1'b0),.key_event(1'b0),.key_code(4'd0),.latest_front_id(32'd55),
 .grant(1'b0),.held(1'b0),.bank(2'd0),.identity(32'd0),.stamp(32'd0),.awready(1'b0),.wready(1'b0),.wlast(1'b0),
 .arready(1'b0),.upload_arready(1'b0),.rdata(256'd0),.rvalid(1'b0),.rlast(1'b0),.upload_rvalid(1'b0),.upload_rlast(1'b0));
 defparam dut.managed_phy.manager.START_CYCLES=20;
 defparam dut.managed_phy.manager.POLL_CYCLES=1000;
 defparam dut.managed_phy.manager.MDIO_HALF=2;
 `include "sim/m361_phy_model.vh"
 reg [7:0] packetmem[0:1499],txmem[0:1499];integer txcount=0,txframes=0,arp_replies=0,hello_replies=0;reg [3:0] lo;reg was_tx=0;reg [31:0] check_crc;
 function [31:0] crc(input [31:0] v,input [7:0] d);reg [31:0] x;integer j;begin x=v;for(j=0;j<8;j++) x=(x[0]^d[j]) ? (x>>1)^32'hedb88320:x>>1;crc=x;end endfunction
 // Conservative pad skew from routed 3.5.1 IO datasheet, plus per-pin
 // mismatch. This checks logic under bounded skew, NOT PCB signoff.
 wire tx_sample;assign #2.038 tx_sample=txc;
 wire [3:0] observed_pins; wire observed_ctl;
 assign #0.036 observed_pins[0]=txpins[0];
 assign #0.035 observed_pins[1]=txpins[1];
 assign #0.031 observed_pins[2]=txpins[2];
 assign #0.009 observed_pins[3]=txpins[3];
 assign #0.000 observed_ctl=txctl;
 reg [7:0] expected_arp[0:59];
 task check_arp; begin
  if(txcount!=72) $fatal(1,"ARP wire length %0d",txcount);
  for(integer j=0;j<7;j++) if(txmem[j]!==8'h55) $fatal(1,"ARP preamble %0d",j);
  for(integer j=0;j<60;j++) if(txmem[j+8]!==expected_arp[j])
   $fatal(1,"ARP byte %0d got=%h expected=%h",j,txmem[j+8],expected_arp[j]);
 end endtask
 always @(posedge tx_sample) begin lo=observed_pins;was_tx=observed_ctl;end
 always @(negedge tx_sample) begin
  if(was_tx) begin if(!observed_ctl) $fatal(1,"TX_CTL error");txmem[txcount]={observed_pins,lo};txcount++;end
  else if(txcount!=0) begin
   if(txcount<72) $fatal(1,"TX runt %0d",txcount);
   check_crc=32'hffffffff;for(integer k=8;k<txcount;k++) check_crc=crc(check_crc,txmem[k]);
   if(check_crc!==32'hdebb20e3 || txmem[7]!==8'hd5) $fatal(1,"TX FCS/framing %h %h",check_crc,txmem[7]);
   if({txmem[20],txmem[21]}==16'h0806 && txmem[29]==2) begin check_arp();arp_replies++;end
   if({txmem[20],txmem[21]}==16'h0800 && txmem[55]==2) hello_replies++;
   txframes++;txcount=0;
  end
 end
 task put16(input integer o,v);begin packetmem[o]=v>>8;packetmem[o+1]=v;end endtask
 task put32(input integer o,input [31:0] v);begin packetmem[o]=v>>24;packetmem[o+1]=v>>16;packetmem[o+2]=v>>8;packetmem[o+3]=v;end endtask
 task send(input integer n,corrupt);reg [31:0] f;begin
  @(negedge source_clk);#1;dv=1;byte_in=8'h55;
  repeat(7) begin @(negedge source_clk);#1;end byte_in=8'hd5;
  @(negedge source_clk);#1;f=32'hffffffff;
  for(integer k=0;k<(n<60?60:n);k++) begin byte_in=k<n ? packetmem[k]:0;f=crc(f,byte_in);@(negedge source_clk);#1;end
  f=~f;for(integer k=0;k<4;k++) begin byte_in=(f>>(8*k))^(corrupt && k==0);@(negedge source_clk);#1;end
  dv=0;byte_in=0;repeat(400) @(negedge source_clk);
 end endtask
 task arp;begin
  for(integer k=0;k<90;k++) packetmem[k]=0;
  for(integer k=0;k<6;k++) packetmem[k]=255;
  for(integer k=6;k<12;k++) packetmem[k]=8'hb0+k;
  put16(12,16'h0806);put16(14,1);put16(16,16'h0800);packetmem[18]=6;packetmem[19]=4;put16(20,1);
  for(integer k=22;k<28;k++) packetmem[k]=8'hb0+k-16;
  for(integer k=0;k<60;k++) expected_arp[k]=0;
  for(integer k=0;k<6;k++) begin expected_arp[k]=8'hb6+k;expected_arp[32+k]=8'hb6+k;end
  {expected_arp[6],expected_arp[7],expected_arp[8],expected_arp[9],expected_arp[10],expected_arp[11]}=48'h020047535632;
  {expected_arp[12],expected_arp[13],expected_arp[14],expected_arp[15],expected_arp[16],expected_arp[17],expected_arp[18],expected_arp[19],expected_arp[20],expected_arp[21]}=80'h08060001080006040002;
  {expected_arp[22],expected_arp[23],expected_arp[24],expected_arp[25],expected_arp[26],expected_arp[27]}=48'h020047535632;
  {expected_arp[28],expected_arp[29],expected_arp[30],expected_arp[31]}=32'hc0a83c02;
  {expected_arp[38],expected_arp[39],expected_arp[40],expected_arp[41]}=32'hc0a83c01;
  put32(28,32'hc0a83c01);put32(38,32'hc0a83c02);send(42,0);
 end endtask
 task hello;integer s;begin
  for(integer k=0;k<90;k++) packetmem[k]=0;
  packetmem[0]=2;packetmem[2]=8'h47;packetmem[3]=8'h53;packetmem[4]=8'h56;packetmem[5]=8'h32;
  for(integer k=6;k<12;k++) packetmem[k]=8'hb0+k;
  put16(12,16'h0800);packetmem[14]=8'h45;put16(16,76);put16(20,16'h4000);packetmem[22]=64;packetmem[23]=17;
  put32(26,32'hc0a83c01);put32(30,32'hc0a83c02);put16(34,50000);put16(36,50000);put16(38,56);
  put32(42,32'h47535633);packetmem[46]=1;packetmem[47]=1;packetmem[49]=1;put32(50,32'h12345678);put16(62,1280);put16(64,720);packetmem[89]=5;
  s=0;for(integer k=14;k<34;k+=2) s=s+{packetmem[k],packetmem[k+1]};s=(s&65535)+(s>>16);put16(24,~s);send(90,0);
 end endtask
 initial begin
  #101;rst=1;@(negedge c);dut.reset_count=(1<<22)-16;
  wait(dut.queue_rx_ready);repeat(40) @(negedge source_clk);
  arp();hello();repeat(1500) @(negedge source_clk);
  if(arp_replies!=1 || hello_replies!=1 || !dut.online) $fatal(1,"link ARP=%0d HELLO=%0d online=%b crc=%0d rx=%0d bad=%0d ready=%b",arp_replies,hello_replies,dut.online,dut.mac.crc_errors,dut.core.rx_packets,dut.core.bad_packets,dut.queue_rx_ready);
  send(90,1);if(dut.mac.crc_errors!=1) $fatal(1,"corrupt CRC accepted");
  repeat(200) @(negedge c);
  if(dut.diag_accept!==32'h00010001 || dut.passive_diagnostics.diag.valid_frames!=2 ||
    dut.passive_diagnostics.diag.nsnap[159:128]!=1) $fatal(1,"diagnostics not observing production MAC/core");
  phy_status=16'h6c00;wait(!dut.phy_ready);repeat(30) @(negedge source_clk);
  arp(); // Raw pins remain observable while the real ready gate holds MAC reset.
  if(dut.passive_diagnostics.diag.raw_frames!=4 || dut.passive_diagnostics.diag.valid_frames!=2 || dut.queue_rx_ready)
    $fatal(1,"ready gating or passive pre-gate visibility");
  phy_status=16'hac00;wait(dut.queue_rx_ready);repeat(40) @(negedge source_clk);
  arp();hello();repeat(1500) @(negedge source_clk);
  if(arp_replies!=2 || hello_replies!=2 || !dut.online || dut.diag_accept!=32'h00020002)
    $fatal(1,"link recovery ARP=%0d HELLO=%0d accepted=%h",arp_replies,hello_replies,dut.diag_accept);
  repeat(200) @(negedge c);
  if(dut.passive_diagnostics.diag.last_arp[415:400]!==16'h0806) $fatal(1,"missing actual TX ARP capture");
  for(integer j=0;j<60;j++) if(dut.passive_diagnostics.diag.last_arp[511-j*8-:8]!==expected_arp[j]) $fatal(1,"ARP capture payload %0d",j);
  if(dut.passive_diagnostics.diag.requests!=dut.passive_diagnostics.diag.completions ||
    dut.passive_diagnostics.diag.completions_dc!=dut.passive_diagnostics.diag.completions)
   $fatal(1,"completion snapshot mismatch");
  check_crc=32'hffffffff;
  for(integer j=8;j<72;j++) check_crc=crc(check_crc,dut.passive_diagnostics.diag.last_arp[575-j*8-:8]);
  if(check_crc!==32'hdebb20e3) $fatal(1,"captured ARP FCS");
  $display("M362_ARP_HEX %0144h",dut.passive_diagnostics.diag.last_arp);
  $display("M362_TX_PASS MDIO_scan=%0d ARP=%0d HELLO=%0d CRC_reject=1 TX_pin_FCS=1 production_ready_reset=1 raw_before_gate=1 telemetry=1 link_recovery=1",transactions,arp_replies,hello_replies);$finish;
 end
 initial begin #3000000;$fatal(1,"timeout addr=%0d step=%0d status=%h ready=%b",dut.managed_phy.manager.address,dut.managed_phy.manager.step,dut.managed_phy.manager.status,dut.phy_ready);end
endmodule
