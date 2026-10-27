"""One endpoint file for this single-link release; no network mutation."""
from pathlib import Path
import ipaddress,json
R=Path(__file__).resolve().parents[1]
c=json.loads((R/'config/m3_endpoints.json').read_text(encoding='utf-8'))
assert c['video_endpoint']==c['front_control_endpoint']==c['current_link']=='port1_pc_combined'
mac=int(c['local_mac'].replace(':',''),16)
s='// Generated from config/m3_endpoints.json; port2 is NOT integrated.\n'
s+=f"`define M31_LOCAL_MAC 48'h{mac:012x}\n"
s+=f"`define M31_LOCAL_IP 32'h{int(ipaddress.IPv4Address(c['board_ip'])):08x}\n"
s+=f"`define M31_HOST_IP 32'h{int(ipaddress.IPv4Address(c['pc_ip'])):08x}\n"
s+=f"`define M31_PORT 16'd{int(c['udp_port'])}\n"
p=R/'rtl/network/m31_endpoints.vh'
if not p.exists() or p.read_text()!=s:p.write_text(s)
