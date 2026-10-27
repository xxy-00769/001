from pathlib import Path
import json,hashlib
r=Path('.')
f=r/'reports'
(f/'port_comparison.json').write_text(json.dumps(dict(source='User completed raw ARP comparison in same chat; baseline 3.5.1 remained programmed',same_OrangePi=True,same_cable=True,host_network_config_changed=False,requests_port1=10,port1_before=dict(rx_all=2014900,rx_good_octets=0,rx_crc=2014900),port1_after=dict(rx_all=2014910,rx_good_octets=640,rx_crc=2014900),port1_delta=dict(rx_all=10,rx_good_octets=640,rx_crc=0),port2_delta=dict(rx_all=10,rx_all_octets=640,rx_good_octets=0,rx_crc=10),conclusion='Failure isolated to port2-specific TX/PHY path; not evidence of unique root cause'),indent=2))
b=Path('E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/release/FPGA_GSV1_M3_06_3_5_1')
bit=b/'FPGA_GSV1_M3_06_3_5_1_NET2_DIAG_HDMI_1080P60.sbit'
(f/'baseline_bit.json').write_text(json.dumps(dict(path=str(bit),sha256=hashlib.sha256(bit.read_bytes()).hexdigest().upper(),expected='51C9986B555DB819EDEA679D44D9C4CD1AADA3B8F068E71609D12A69F14F63A2'),indent=2))
# Retain the detailed baseline routed pad report, including both polarities.
import shutil
shutil.copy2('query_tx.log',f/'baseline_tx_io_datasheet.log')
(f/'tx_path_audit.json').write_text(json.dumps(dict(pins={'TXC':'C20','TX_CTL':'F22','TXD3':'F21','TXD2':'E22','TXD1':'E20','TXD0':'C22'},sources=['MES50HP hardware manual table3-2','11_ethernet_test.rar/ethernet_test.fdc commented port2 pin set','published 3.5.1 mapped netlist'],mac_core_changed=False,phy_management_changed=False,rgmii_serializer_changed=False,net1_changed=False,PLL_or_phase_changed=False,TX_delay_readback='BD75',TX_internal_delay='Enabled (page7/extA4/reg1C bits13:11 all1); datasheet TXDLY nominal2ns',CLK_PLL_difference='Official example and port1 use local PLL; port2 uses RXC BUFG with PHY internal delay. No cross-port clock borrowing.',warning='Matched-polarity IO datasheet differences of 2..38ps do not bound opposite-polarity transitions. No board electrical signoff is claimed.'),indent=2))
