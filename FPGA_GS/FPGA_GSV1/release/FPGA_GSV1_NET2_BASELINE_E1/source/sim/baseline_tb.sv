`timescale 1ns/1ps
module baseline_tb;
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 reg sys=0,rxc=0;
 always #10 sys=~sys;
 always #4 rxc=~rxc;
 reg p0=0,p1=0;
 initial begin #4;forever #4 p0=~p0;end
 initial begin #5;forever #4 p1=~p1;end
 reg rxctl=0;reg [3:0] rxdata=0;
 wire txc,txctl,phyreset;wire [3:0] txdata;
 net2_official_baseline #(.RESET_CYCLES(4),.ARP_PERIOD(3000)) dut(
  .clk_50m(sys),.phy_rstn(phyreset),.rgmii_rxc(rxc),.rgmii_rx_ctl(rxctl),.rgmii_rxd(rxdata),
  .rgmii_txc(txc),.rgmii_tx_ctl(txctl),.rgmii_txd(txdata));
 // Use the exact PLL waveforms independently confirmed by PNR, so the
 // vendor PLL oscillator model is not part of this short packet simulation.
 initial begin
  force dut.phase0=p0;force dut.phase1=p1;
  force dut.ref_lock=0;force dut.phase_lock=0;
  #103;force dut.ref_lock=1;force dut.phase_lock=1;
 end
 function [31:0] crc(input [31:0] v,input [7:0] b);
 reg [31:0] x;integer i;begin x=v;for(i=0;i<8;i=i+1)
  x=(x[0]^b[i]) ? (x>>1)^32'hedb88320:x>>1;crc=x;end endfunction
 reg [7:0] request[0:71],frame[0:255];
 reg [31:0] c;integer i,j;
 // RX fixture assumes strap-mode (no PHY RX internal delay):
 // PHY data arrives 1ns after external RXC. This is a declared logical
 // test waveform, not a measurement or a guarantee of the board RX eye.
 task send_request;
 begin
  @(posedge rxc);#1;
  for(j=0;j<72;j=j+1) begin rxctl=1;rxdata=request[j][3:0];#4;rxdata=request[j][7:4];#4;end
  rxctl=0;rxdata=0;
 end endtask
 wire sampleclk,ctl;wire [3:0] pins;
 assign #0.080 sampleclk=txc;
 assign #0.036 pins=txdata;assign #0.009 ctl=txctl;
 reg [3:0] low;reg valid_low;
 integer logfd;initial logfd=$fopen("reports/pin_frames.hex","w");
 integer n=0,frames=0,replies=0,probes=0,idles=0,min_ifg=999999;
 reg previous=0;
 always @(posedge sampleclk) begin low=pins;valid_low=ctl;end
 always @(negedge sampleclk) begin
  if(valid_low) begin
   if(ctl!==1'b1) $fatal(1,"TX_CTL DDR mismatch");
   if(n==0 && previous) begin
    if(idles<12) $fatal(1,"IFG too short %0d",idles);
    if(idles<min_ifg) min_ifg=idles;
   end
   frame[n]={pins,low};n=n+1;idles=0;
  end else begin
   if(n!=0) begin
    for(i=0;i<n;i=i+1)$fwrite(logfd,"%02h",frame[i]);$fwrite(logfd,"\n");
    if(n!=73) $fatal(1,"official frame length %0d",n);
    for(i=0;i<7;i=i+1) if(frame[i]!==8'h55) $fatal(1,"preamble %0d %h",i,frame[i]);
    if(frame[7]!==8'hd5) $fatal(1,"SFD");
    c=32'hffffffff;for(i=8;i<n;i=i+1)c=crc(c,frame[i]);
    if(c!==32'hdebb20e3) $fatal(1,"pin FCS %h",c);
    if({frame[14],frame[15],frame[16],frame[17],frame[18],frame[19]}!==48'h020047535632)
     $fatal(1,"source MAC");
    if({frame[20],frame[21]}!==16'h0806) $fatal(1,"ethertype");
    if({frame[36],frame[37],frame[38],frame[39]}!==32'hc0a83c02) $fatal(1,"source IP");
    if({frame[46],frame[47],frame[48],frame[49]}!==32'hc0a83c01) $fatal(1,"target IP");
    if(frame[29]==2) begin
     if({frame[8],frame[9],frame[10],frame[11],frame[12],frame[13]}!==48'h0000a4b55fef) $fatal(1,"reply DA");
     replies=replies+1;
    end else if(frame[29]==1) probes=probes+1;
    else $fatal(1,"opcode");
    frames=frames+1;n=0;previous=1;
   end
   idles=idles+1;
  end
 end
 initial begin
  for(i=0;i<72;i=i+1) request[i]=0;
  for(i=0;i<7;i=i+1)request[i]=8'h55;request[7]=8'hd5;
  for(i=8;i<14;i=i+1)request[i]=8'hff;
  {request[14],request[15],request[16],request[17],request[18],request[19]}=48'h0000a4b55fef;
  {request[20],request[21],request[22],request[23],request[24],request[25]}=48'h080600010800;
  {request[26],request[27],request[28],request[29]}=32'h06040001;
  {request[30],request[31],request[32],request[33],request[34],request[35]}=48'h0000a4b55fef;
  {request[36],request[37],request[38],request[39]}=32'hc0a83c01;
  {request[46],request[47],request[48],request[49]}=32'hc0a83c02;
  c=~0;for(i=8;i<68;i=i+1)c=crc(c,request[i]);c=~c;
  {request[71],request[70],request[69],request[68]}=c;
  wait(dut.rstn);#600;
  repeat(3) begin send_request();#3000;end
  wait(replies==3 && probes>=2);#100;
  $display("E1_PIN_PASS replies=%0d periodic_arp=%0d frames=%0d min_ifg=%0d MAC_FCS_verified=1",replies,probes,frames,min_ifg);
  $fclose(logfd);$finish;
 end
 initial begin #150000;$fatal(1,"timeout replies=%0d probes=%0d",replies,probes);end
endmodule
