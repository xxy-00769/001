"""Synthetic profile tests, never hardware acceptance."""
import importlib.util,json
from pathlib import Path
w=Path(__file__).parents[1]
spec=importlib.util.spec_from_file_location('dec',w/'tools/cam0/decode_cam0.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
a=json.loads((w/'reports/hardware_baseline/CAM0_BASELINE_20261024_112313_959.json').read_text(encoding='utf-8-sig'))
reg={int(k,16):int(v,16) for k,v in a['snapshots'][0]['registers'].items()}
reg.update({0x3500:0,0x3501:0x0d,0x3502:0xe0,0x3503:0,0x3a00:0x78,
0x3a02:0,0x3a03:222,0x3a14:0,0x3a15:222,0x3a18:0,0x3a19:128,
0x3a08:0,0x3a09:222,0x3a0a:0,0x3a0b:185,0x3a0d:0xc1,0x3a0e:0x81,0x3c00:4,0x3c01:0xb4})
def fixtures(overexposure=False,fail=False):
 r=reg.copy()
 if overexposure:r[0x3501]=0x2e;r[0x3502]=0
 b=bytes(r[v] for v in m.REGS);words=[0]*40
 words[20]=0x43304d39;words[21]=921600;words[22]=(1<<26)|(1<<25)|720|(int(fail)<<24)
 words[29:40]=[int.from_bytes(b[i:i+4],'big') for i in range(0,44,4)]
 records=[]
 for i in range(11):
  words[23]=30*i;words[24]=1000*i;words[25]=15*i<<16|15*i;words[26]=1000*i;words[28]=2252<<16|i<<8
  records.append(m.decode(words))
 return m.summarize(records)
r=fixtures();assert r['completed'] and r['motion_profile_verified'] and r['motion_metrics_ok']
assert abs(r['snapshots'][-1]['exposure_ms']-9.99888)<1e-8
assert r['capture_fps']==30 and r['ddr_publish_fps']==15 and r['display_new_fps']==15
r=fixtures(overexposure=True);assert r['completed'] and not r['motion_metrics_ok']
r=fixtures(fail=True);assert not r['completed'] and not r['motion_profile_verified']
print('PASS synthetic motion decoder: C0M9, preserved band debug bits, measured10ms/8x, distinct30/15/15 rates, profile failure and excessive actual exposure rejected')
