from pathlib import Path
r=Path('.')
p=r/'sim/m361_link_tb.sv'
s=p.read_text();s=s.replace('module m361_link_tb;','module m362_tx_tb;')
s=s.replace("wire tx_sample;assign #2 tx_sample=txc;",'''// Conservative pad skew from routed 3.5.1 IO datasheet, plus per-pin
 // mismatch. This checks logic under bounded skew, NOT PCB signoff.
 wire tx_sample;assign #2 tx_sample=txc;
 wire [3:0] observed_pins; wire observed_ctl;
 assign #0.002 observed_pins[0]=txpins[0];
 assign #0.003 observed_pins[1]=txpins[1];
 assign #0.007 observed_pins[2]=txpins[2];
 assign #0.029 observed_pins[3]=txpins[3];
 assign #0.038 observed_ctl=txctl;
 reg [7:0] expected_arp[0:59];
 task check_arp; begin
  if(txcount!=72) $fatal(1,"ARP wire length %0d",txcount);
  for(integer j=0;j<7;j++) if(txmem[j]!==8'h55) $fatal(1,"ARP preamble %0d",j);
  for(integer j=0;j<60;j++) if(txmem[j+8]!==expected_arp[j])
   $fatal(1,"ARP byte %0d got=%h expected=%h",j,txmem[j+8],expected_arp[j]);
 end endtask''')
s=s.replace('lo=txpins;was_tx=txctl;', 'lo=observed_pins;was_tx=observed_ctl;').replace('if(!txctl)', 'if(!observed_ctl)').replace('{txpins,lo}', '{observed_pins,lo}')
s=s.replace('arp_replies++;','begin check_arp();arp_replies++;end')
s=s.replace('for(integer k=22;k<28;k++) packetmem[k]=8\'hb0+k-16;', '''for(integer k=22;k<28;k++) packetmem[k]=8'hb0+k-16;
  for(integer k=0;k<60;k++) expected_arp[k]=0;
  for(integer k=0;k<6;k++) begin expected_arp[k]=8'hb6+k;expected_arp[32+k]=8'hb6+k;end
  {expected_arp[6],expected_arp[7],expected_arp[8],expected_arp[9],expected_arp[10],expected_arp[11]}=48'h020047535632;
  {expected_arp[12],expected_arp[13],expected_arp[14],expected_arp[15],expected_arp[16],expected_arp[17],expected_arp[18],expected_arp[19],expected_arp[20],expected_arp[21]}=80'h08060001080006040002;
  {expected_arp[22],expected_arp[23],expected_arp[24],expected_arp[25],expected_arp[26],expected_arp[27]}=48'h020047535632;
  {expected_arp[28],expected_arp[29],expected_arp[30],expected_arp[31]}=32'hc0a83c02;
  {expected_arp[38],expected_arp[39],expected_arp[40],expected_arp[41]}=32'hc0a83c01;''')
s=s.replace('M361_LINK_PASS','M362_TX_PASS')
(r/'sim/m362_tx_tb.sv').write_text(s)
s=(r/'scripts/check_m361.py').read_text().replace("O=R/'reports/m361_checks'", "O=R/'reports/m362_checks'")
s=s.replace("('link',['sim/m361_link_tb.sv']+common),('diag',['sim/m361_diag_tb.sv','rtl/network/m361_diag.v'])", "('tx',['sim/m362_tx_tb.sv']+common)")
s=s.replace("top='m361_'+name+'_tb'", "top='m362_'+name+'_tb'").replace("'M361_'+name.upper()+'_PASS'", "'M362_'+name.upper()+'_PASS'")
s=s.replace("'sim/m361_link_tb.sv'", "'sim/m362_tx_tb.sv'")
(r/'scripts/check_m362.py').write_text(s)
