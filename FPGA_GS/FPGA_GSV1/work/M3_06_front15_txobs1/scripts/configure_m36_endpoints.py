"""Generate the two hardware endpoints; never mutate host networking."""
from pathlib import Path
import ipaddress, json
R = Path(__file__).resolve().parents[1]
c = json.loads((R/'config/m3_endpoints.json').read_text(encoding='utf-8'))
s = '// Generated from config/m3_endpoints.json (M3-06 dual Ethernet).\n'
for role, prefix in [('right', 'M31'), ('front-control', 'M36_P2')]:
    e = c['endpoints'][role]
    fields = [('LOCAL_MAC' if role == 'right' else 'MAC', 48, int(e['local_mac'].replace(':',''),16)),
              ('LOCAL_IP' if role == 'right' else 'IP', 32, int(ipaddress.IPv4Address(e['board_ip']))),
              ('HOST_IP' if role == 'right' else 'HOST', 32, int(ipaddress.IPv4Address(e['host_ip'])))]
    for key, bits, value in fields:
        s += f"`define {prefix}_{key} {bits}'h{value:0{bits//4}x}\n"
    s += f"`define {prefix}_PORT 16'd{int(e['udp_port'])}\n"
p = R/'rtl/network/m31_endpoints.vh'
if not p.exists() or p.read_text() != s:
    p.write_text(s)
