from pathlib import Path
r=Path('.')
p=r/'rtl/network/m361_diag.v';s=p.read_text()
s=s.replace('reg [31:0] requests,completions;reg req_last,ack_last;', '''reg [31:0] requests,completions;reg req_last;
 // Count completion in the MAC clock domain, then transfer a held snapshot.
 // Never use asynchronous tx_ack as a combinational increment enable in dc.
 reg ack_last;
 always @(posedge nc or negedge rst_n) if(!rst_n) begin completions<=0;ack_last<=0;end
 else begin
  ack_last<=tx_ack;
  if(mac_ready && tx_ack!=ack_last) completions<=completions+1'b1;
 end
 wire [31:0] completions_dc;
 m361_snapshot completion_snapshot(.sc(nc),.dc(dc),.rst_n(rst_n),.value(completions),.snapshot(completions_dc));''')
s=s.replace('requests<=0;completions<=0;req_last<=0;ack_last<=0;', 'requests<=0;req_last<=0;')
s=s.replace('req_last<=tx_req;ack_last<=tx_ack;', 'req_last<=tx_req;')
s=s.replace("  if(core_ready && tx_ack!=ack_last) completions<=completions+1'b1;\n",'')
s=s.replace('aborts,requests,completions,', 'aborts,requests,completions_dc,')
s=s.replace('4:character="5";5:character="1";', '4:character="5";5:character="2";')
p.write_text(s)
p=r/'tools/m3/decode_net2_diag.py';s=p.read_text().replace("fields[:2]!=['N2','351']", "fields[:2] not in (['N2','351'],['N2','352'])");s=s.replace("d=dict(zip(names,w[4:]))", "d=dict(zip(names,w[4:]));d['diagnostic_version']=fields[1]")
p.write_text(s)
p=r/'tools/m3/read_net2_diag.ps1';s=p.read_text().replace('^N2 351 ', '^N2 35[12] ').replace('No N2 351 line','No N2 351/352 line');p.write_text(s)
p=r/'scripts/build_m36.ps1';p.write_text(p.read_text().replace('3_5_1','3_5_2').replace('3.5.1','3.5.2'))
p=r/'constraints/mes50hp.fdc';s=p.read_text();s+='''
# Port2 TX: constrain edge-aligned RGMII transmitter skew to +/-0.5ns
# (RTL8211E rev1.6 Table65 TskewT). The forwarded pad clock is propagated,
# not a virtual zero-insertion clock. PHY internal 2ns capture delay is NOT
# added to this clock: this checks the FPGA transmitter, not PCB signoff.
create_generated_clock -name eth2_txc_pad -source [get_ports {rgmii2_rxc}] -master_clock [get_clocks {eth2_rxc}] -edges {1 2 3} [get_ports {rgmii2_txc}]
set_output_delay -clock [get_clocks {eth2_txc_pad}] -max 3.500 [get_ports {rgmii2_txd[*] rgmii2_tx_ctl}]
set_output_delay -clock [get_clocks {eth2_txc_pad}] -min -0.500 [get_ports {rgmii2_txd[*] rgmii2_tx_ctl}]
set_output_delay -clock [get_clocks {eth2_txc_pad}] -clock_fall -add_delay -max 3.500 [get_ports {rgmii2_txd[*] rgmii2_tx_ctl}]
set_output_delay -clock [get_clocks {eth2_txc_pad}] -clock_fall -add_delay -min -0.500 [get_ports {rgmii2_txd[*] rgmii2_tx_ctl}]
''';p.write_text(s)
