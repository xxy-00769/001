"""Synthetic fixtures, NEVER hardware acceptance evidence."""
import importlib.util
from pathlib import Path
spec=importlib.util.spec_from_file_location('decoder',Path(__file__).parents[1]/'tools/cam0/decode_cam0.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
b=bytearray(44)
values={0x300a:0x56,0x300b:0x40,0x3500:0,0x3501:0x2d,0x3502:0,
0x3503:0,0x350a:0,0x350b:0x20,0x380c:7,0x380d:0x64,0x380e:2,0x380f:0xe4,
0x3a00:0x78,0x3a18:0,0x3a19:0xf8,0x3a08:0,0x3a09:0x6f,0x3a0a:0,0x3a0b:0x5c}
for i,r in enumerate(m.REGS):b[i]=values.get(r,0)
def words(ms,seq,good,pub,display):
 w=[0]*40;w[20]=0x43304f39;w[21]=921600;w[22]=(1<<26)|(1<<25)|720
 w[23]=good;w[24]=ms;w[25]=pub<<16|display;w[26]=ms;w[27]=84000000
 w[28]=2252<<16|seq<<8
 w[29:40]=[int.from_bytes(b[i:i+4],'big') for i in range(0,44,4)]
 return w
a=m.decode(words(1000,1,65500,65500,65500));z=m.decode(words(11000,10,264,114,114))
# Exposure720 rows *45.04us =32.4288ms; not720ms and not /2 for RGB565.
assert abs(a['exposure_ms']-32.4288)<1e-8
assert a['gain_x']==2 and a['gain_ceiling_x']==15.5
assert abs(a['band_50_ms']-4.99944)<1e-6
r=m.summarize([m.decode(words(1000+i*1000,i+1,(65500+i*30)&65535,
    (65500+i*15)&65535,(65500+i*15)&65535)) for i in range(11)])
assert r['completed'] and r['capture_fps']==30 and r['ddr_publish_fps']==15 and r['display_new_fps']==15
# Readers must distinguish sensor capture30, DDR/display15 and HDMI60.
w=words(11000,10,264,114,114);w[22]&=~(1<<26)
assert not m.summarize([a,m.decode(w)])['completed']
w=words(11000,10,264,114,114);w[31]^=0x00000001
assert m.decode(w)['exposure_ms'] is None
assert not m.summarize([a,a])['completed']
assert not m.summarize([])['completed']
print('PASS synthetic CAM0 decoder: row/exposure ms, gain, band period, counter wrap, capture/publication separation, NACK invalidation, torn exposure, missing/stale input')
