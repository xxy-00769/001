"""Cross-check production PLL/SDC/AVI and the saved physical 27B1 EDID."""
from pathlib import Path
import hashlib,json,re
R=Path(__file__).resolve().parents[1]
raw=(R/'reports/M3_03_EDID/27B1.bin').read_bytes()
b=raw[54:72];hb=b[3]+((b[4]&15)<<8);vb=b[6]+((b[7]&15)<<8)
hf=b[8]+((b[11]>>6)<<8);hs=b[9]+(((b[11]>>4)&3)<<8)
vf=(b[10]>>4)+(((b[11]>>2)&3)<<4);vs=(b[10]&15)+((b[11]&3)<<4)
preferred=dict(PixelHz=int.from_bytes(b[:2],'little')*10000,
    HFront=hf,HSync=hs,HBack=hb-hf-hs,VFront=vf,VSync=vs,VBack=vb-vf-vs,
    HSPositive=bool(b[17]&2),VSPositive=bool(b[17]&4))
assert preferred==dict(PixelHz=148500000,HFront=88,HSync=44,HBack=148,
    VFront=4,VSync=5,VBack=36,HSPositive=True,VSPositive=True),preferred
pll=(R/'rtl/display/m31_pixel_pll.v').read_text()
p={n:int(re.search(r'\b'+n+r'\s*=\s*(\d+)',pll).group(1)) for n in
    ['STATIC_RATIOI','STATIC_RATIOF','STATIC_RATIO0','STATIC_DUTY0']}
assert 50e6*p['STATIC_RATIOF']/p['STATIC_RATIOI']/p['STATIC_RATIO0']==148500000
assert p['STATIC_DUTY0']==p['STATIC_RATIO0']
fdc=(R/'constraints/mes50hp.fdc').read_text()
line=next(s for s in fdc.splitlines() if 'create_generated_clock -name {pix_clk}' in s)
assert '-multiply_by {297} -divide_by {100}' in line
top=(R/'rtl/board/fpga_gsv1_top.v').read_text();assert '.AVI_VIC(16)' in top
assert '.HOLD_CYCLES(297000000)' in top
init=(R/'rtl/reuse/ms7210_ctl.v').read_text()
assert "{16'h1281,8'h04}" in init
assert "(8'h06-AVI_VIC[7:0])" in init
result=dict(Verdict='PASS',EDIDPreferred=preferred,PLLParameters=p,
    GeneratedClockConstraint=line,PixelPeriodNs=1e9/148500000,AVI_VIC=16,AVI_Checksum=246,
    MS7210PAInvert=4,DisplayReadMBps=dict(Single=110.592,Quad=331.776),
    Four720p30WritePlusFront5ReadPlusQuadMBps=562.176,
    BoardSignalMeasured=False,ExternalIoTimingSignoff=False)
consumed=['reports/M3_03_EDID/27B1.bin','rtl/display/m31_pixel_pll.v',
    'constraints/mes50hp.fdc','rtl/board/fpga_gsv1_top.v','rtl/reuse/ms7210_ctl.v']
result['Inputs']={str(R/f):hashlib.sha256((R/f).read_bytes()).hexdigest() for f in consumed}
(R/'reports/M3_03_format_audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))
