# ARCHIVAL GENERATOR: NOT an execution step; final checked-in testbenches are authoritative.
raise SystemExit("Use scripts/check_m364.py with final sim/m364_* files")
from pathlib import Path
import re
R=Path(__file__).resolve().parents[1]
W=R.parent/'M3_06_fix_3_5_3'
s=(W/'sim/m363_tx_tb.sv').read_text()
s=re.sub(r'module GTP_CLKBUFG.*?module m363_tx_tb;', 'module m364_tx_tb;',s,flags=re.S)
s=s.replace('wire rxc;assign #2 rxc=source_clk;','wire rxc=source_clk;')
s=s.replace('begin pins=byte_in[3:0];ctl=dv;end','begin #1; pins=byte_in[3:0];ctl=dv;end')
s=s.replace('begin pins=byte_in[7:4];ctl=dv;end','begin #1; pins=byte_in[7:4];ctl=dv;end')
s=s.replace('.PHY_INTERNAL_DELAY(1)', '.PHY_INTERNAL_DELAY(1),.E1_PHY(1)')
s=s.replace('dut.managed_phy.manager','dut.e1_phy.manager')
s=s.replace('assign #2.038 tx_sample=txc;', 'assign #0.080 tx_sample=txc;')
s=s.replace('dut.reset_count=(1<<22)-16','dut.reset_count=1000000-16')
start=s.index('  if(dut.diag_accept!==')
end=s.index('  phy_status=',start)
s=s[:start]+'''  if(dut.diag_accept!==32'h00010001) $fatal(1,"accept counters");
  if(delay_reg!==16'h0123) $fatal(1,"strap delay was modified");
'''+s[end:]
start=s.index('  if(dut.passive_diagnostics.diag.raw_frames')
end=s.index('  phy_status=',start)
s=s[:start]+'''  if(dut.queue_rx_ready) $fatal(1,"link-down queue gating");
'''+s[end:]
start=s.index('  if(dut.passive_diagnostics.diag.last_arp')
end=s.index('  for(integer j=0;j<8;j++)',start)
s=s[:start]+'''  // Exercise PLL lock loss through the real async reset and release path.
  force dut.e1_phy.pll.pll_lock=0;
  #21;if(dut.queue_rx_ready || dut.queue_mac_ready) $fatal(1,"PLL loss reset");
  #100;release dut.e1_phy.pll.pll_lock;
  wait(dut.queue_rx_ready);repeat(40) @(negedge source_clk);
'''+s[end:]
s=re.sub(r'  \$display\("M363_ARP_HEX.*?;\n','',s)
s=s.replace('M363_','M364_').replace('raw_before_gate=1 telemetry=1','strap_unchanged=1 pll_recovery=1')
(R/'sim/m364_tx_tb.sv').write_text(s)
s=(W/'sim/m363_burst_tb.sv').read_text().replace('m363_burst_tb','m364_burst_tb')
s=s.replace(' m36_rgmii_interface io(.rst(!run),.rst90(!run),.rgmii_rxc_phase_d(1\'b0),', ''' wire phase0,phase1;
 m3_eth_pll pll(.clkin1(rxc),.clkout0(phase0),.clkout1(phase1),.pll_lock());
 reg [7:0] tx_data;reg tx_valid;
 always @(posedge nc) if(!run) begin tx_data<=0;tx_valid<=0;end
 else begin tx_data<=gmii;tx_valid<=valid;end
 m364_e1_rgmii io(.rst(!run),.rgmii_rxc_phase_d(phase1),''')
s=s.replace('.mac_tx_data_valid(valid),.mac_tx_data(gmii)', '.mac_tx_data_valid(tx_valid),.mac_tx_data(tx_data)')
s=s.replace('.rgmii_rxc(rxc)', '.rgmii_rxc(phase0)')
s=s.replace('assign #2.038 sample_clock=txc;', 'assign #0.080 sample_clock=txc;')
s=s.replace(' serialreset=%b stream=%b','').replace(',io.tx_serial_reset,io.tx_streaming','')
s=s.replace('M363_','M364_')
(R/'sim/m364_burst_tb.sv').write_text(s)
