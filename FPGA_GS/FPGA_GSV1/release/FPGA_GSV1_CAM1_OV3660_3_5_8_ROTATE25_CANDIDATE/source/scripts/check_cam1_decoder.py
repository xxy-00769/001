"""Synthetic UART fixture only; never a hardware performance result."""
from pathlib import Path
import subprocess
import json
import sys

root = Path(__file__).resolve().parents[1]
path = root/'reports/C1R8_synthetic_fixture.txt'
lines = []
for i in range(61):
    w = [0]*40
    w[12] = 0x43315238
    w[13] = 921600
    w[14] = 0x07000000 | 720
    count = (65000+i*25) & 65535
    w[15] = count
    w[16] = 10000+i*1000
    w[17] = (count << 16) | count
    w[18] = 10040+i*1000
    w[19] = 72000000
    lines.append('N2 35O '+' '.join(f'{v:08X}' for v in w))
path.write_text('\n'.join(lines)+'\n')
dest = path.with_suffix('.json')
cmd = [sys.executable, '-X', 'utf8', str(root/'scripts/decode_cam1_rate.py'),
       str(path), '--output', str(dest), '--minimum-window', '60']
r = subprocess.run(cmd, capture_output=True)
assert r.returncode == 0, r.stderr
j = json.loads(dest.read_text(encoding='utf-8'))
assert j['rate_quality_pass'] and j['ddr_publish_delta'] == 1500
assert j['capture_fps'] == j['ddr_publish_fps'] == j['display_new_fps'] == 25
assert j['snapshots'][-1]['inferred_xclk_hz'] == 24000000
invalid = root/'reports/C1R8_synthetic_wrong_tag.txt'
invalid.write_text(lines[0].replace('43315238', '43314731')+'\n')
r = subprocess.run(cmd[:4]+[str(invalid)], capture_output=True)
assert r.returncode != 0
reset = root/'reports/C1R8_synthetic_reset.txt'
reset.write_text('\n'.join([lines[1],lines[0]])+'\n')
r = subprocess.run(cmd[:4]+[str(reset)], capture_output=True)
assert r.returncode != 0
print('PASS synthetic decoder: atomic60s windows,three distinct rates,16bit wrap,geometry,measured/inferred clocks,missing/new-tag refusal; NOT board data')
