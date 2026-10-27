from pathlib import Path
p=Path('sim/m362_tx_tb.sv');s=p.read_text().replace('  $display("M362_TX_PASS', '''  check_crc=32'hffffffff;
  for(integer j=8;j<72;j++) check_crc=crc(check_crc,dut.passive_diagnostics.diag.last_arp[575-j*8-:8]);
  if(check_crc!==32'hdebb20e3) $fatal(1,"captured ARP FCS");
  $display("M362_ARP_HEX %0144h",dut.passive_diagnostics.diag.last_arp);
  $display("M362_TX_PASS''');p.write_text(s)
p=Path('scripts/check_m362.py');s=p.read_text().replace('import os,subprocess,json,hashlib,sys','import os,subprocess,json,hashlib,sys,re,importlib.util')
s=s.replace("results['InputsUnchanged']=", '''spec=importlib.util.spec_from_file_location('diag_decoder',R/'tools/m3/decode_net2_diag.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
raw=re.search(r'M362_ARP_HEX ([0-9a-fA-F]{144})',(O/'tx.log').read_text()).group(1)
decoded=module.decode('N2 352 '+'00000000 '*22+' '.join(raw[i:i+8] for i in range(0,144,8)))
assert decoded['last_mac_tx_arp']['fcs_valid'] and decoded['last_mac_tx_arp']['zero_padding']
assert decoded['last_mac_tx_arp']['destination_mac']=='b6:b7:b8:b9:ba:bb'
(O/'captured_arp_decoded.json').write_text(json.dumps(decoded,indent=2))
results['ActualCapturedARPDecoder']=True
results['InputsUnchanged']=''')
s=s.replace("inputs=set(common+", "inputs=set(['tools/m3/decode_net2_diag.py']+common+")
p.write_text(s)
