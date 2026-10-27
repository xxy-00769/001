"""Read only the Windows registry EDID for the identified AOC 27B1."""
from pathlib import Path
import winreg, json, hashlib, datetime
R=Path(__file__).resolve().parents[1]; D=R/'reports/M3_03_EDID';D.mkdir(exist_ok=True)
root=r'SYSTEM\CurrentControlSet\Enum\DISPLAY\AOC2701'
with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,root) as k:instance=winreg.EnumKey(k,0)
with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE,root+'\\'+instance+r'\Device Parameters') as k:raw=winreg.QueryValueEx(k,'EDID')[0]
assert raw[:8]==bytes.fromhex('00ffffffffffff00') and len(raw)==128*(1+raw[126])
checks=[sum(raw[i:i+128])%256 for i in range(0,len(raw),128)];assert not any(checks)
def dtd(b):
    if int.from_bytes(b[:2],'little')==0:return None
    p=int.from_bytes(b[:2],'little')*10000
    h=b[2]+((b[4]>>4)<<8);hb=b[3]+((b[4]&15)<<8)
    v=b[5]+((b[7]>>4)<<8);vb=b[6]+((b[7]&15)<<8)
    return dict(Width=h,Height=v,PixelHz=p,HTotal=h+hb,VTotal=v+vb,Fps=p/((h+hb)*(v+vb)),Flags=b[17])
descriptors=[raw[i:i+18] for i in range(54,126,18)]
name=next(b[5:18].decode('ascii').strip() for b in descriptors if b[:5]==b'\0\0\0\xfc\0');assert name=='27B1'
ranges=[dict(VMin=b[5],VMax=b[6],HMinKHz=b[7],HMaxKHz=b[8],MaxPixelMHz=b[9]*10)
        for b in descriptors if b[:5]==b'\0\0\0\xfd\0']
modes=[];details=[dtd(b) for b in descriptors if dtd(b)]
for start in range(128,len(raw),128):
    b=raw[start:start+128]
    if b[0]!=2:continue
    at=4
    while at<b[2]:
        tag,n=b[at]>>5,b[at]&31
        if tag==2:modes.extend(v&127 for v in b[at+1:at+1+n])
        at+=1+n
    details.extend(dtd(b[i:i+18]) for i in range(b[2],110,18) if dtd(b[i:i+18]))
(D/'27B1.bin').write_bytes(raw)
result=dict(Verdict='PASS',Monitor=name,RegistryPath=root+'\\'+instance,RawBytes=len(raw),
    SHA256=hashlib.sha256(raw).hexdigest(),BlockChecksums=checks,Range=ranges,
    CTAVICs=modes,DetailedTimings=details,AdvertisesVIC16=16 in modes,
    AdvertisesVIC34=34 in modes,BoardSignalMeasured=False,ReadTime=datetime.datetime.now().astimezone().isoformat())
(D/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result,indent=2))
