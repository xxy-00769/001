from pathlib import Path
r=Path('.')
p=r/'rtl/network/m361_diag.v';s=p.read_text().replace('raw_ctl,rxv,txv,','raw_ctl,rxv,txv,input [7:0] txd,')
a=''' // Last complete minimum-sized ARP as actually emitted by production MAC,
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
'''
s=s.replace(' wire [703:0] values=',a+' wire [1279:0] values=')
s=s.replace("29'd0,phy_rstn,core_sync[1],mac_sync[1]};", "29'd0,phy_rstn,core_sync[1],mac_sync[1],arp_snapshot};")
s=s.replace('input [703:0] values','input [1279:0] values').replace('reg [703:0] held;reg [7:0] index;', 'reg [1279:0] held;reg [8:0] index;')
s=s.replace('205:character=13;206:character=10;', '367:character=13;368:character=10;').replace('index<205','index<367').replace('held[703-', 'held[1279-').replace('index==206','index==368')
s=s.replace('One atomic line/second; all fields hexadecimal.', 'One atomic line/second; 22 status words + 18 words of last ARP TX bytes.')
p.write_text(s)
p=r/'rtl/network/m3_network.v';s=p.read_text().replace('.raw_ctl(rgmii_rx_ctl),.rxv(rxv),.txv(txv),', '.raw_ctl(rgmii_rx_ctl),.rxv(rxv),.txv(txv),.txd(txd),');p.write_text(s)
p=r/'sim/m362_tx_tb.sv';s=p.read_text().replace('  $display("M362_TX_PASS', '''  repeat(200) @(negedge c);
  for(integer j=0;j<72;j++) if(dut.passive_diagnostics.diag.last_arp[575-j*8-:8]!==txmem[j]) begin
   // The most recent frame is HELLO, so compare ARP fields independently.
  end
  if(dut.passive_diagnostics.diag.last_arp[415:400]!==16'h0806) $fatal(1,"missing actual TX ARP capture");
  for(integer j=0;j<60;j++) if(dut.passive_diagnostics.diag.last_arp[511-j*8-:8]!==expected_arp[j]) $fatal(1,"ARP capture payload %0d",j);
  if(dut.passive_diagnostics.diag.requests!=dut.passive_diagnostics.diag.completions ||
    dut.passive_diagnostics.diag.completions_dc!=dut.passive_diagnostics.diag.completions)
   $fatal(1,"completion snapshot mismatch");
  $display("M362_TX_PASS''')
# Remove meaningless comparison loop (HELLO is intentionally the last frame).
s=s.replace('''  for(integer j=0;j<72;j++) if(dut.passive_diagnostics.diag.last_arp[575-j*8-:8]!==txmem[j]) begin
   // The most recent frame is HELLO, so compare ARP fields independently.
  end
''','')
p.write_text(s)
p=r/'sim/m361_diag_tb.sv';s=p.read_text().replace('703:0','1279:0').replace('0:206','0:368').replace('22;i++','40;i++').replace('703-','1279-').replace('207;i++','369;i++').replace('"N2 351 "','"N2 352 "').replace('got[205]','got[367]').replace('got[206]','got[368]').replace('i<205','i<367').replace('atomic_22_words','atomic_40_words').replace('#30000000','#40000000');p.write_text(s)
p=r/'scripts/check_m362.py';s=p.read_text().replace("('tx',['sim/m362_tx_tb.sv']+common)", "('tx',['sim/m362_tx_tb.sv']+common),('diag',['sim/m361_diag_tb.sv','rtl/network/m361_diag.v'])").replace("top='m362_'+name+'_tb'", "top=('m361_' if name=='diag' else 'm362_')+name+'_tb'").replace("'M362_'+name.upper()+'_PASS'", "('M361_' if name=='diag' else 'M362_')+name.upper()+'_PASS'");p.write_text(s)
