from pathlib import Path
import argparse, hashlib, json, shutil, datetime, re
P=argparse.ArgumentParser()
for n in ['build','full','unit','m2','vendor','processing']: P.add_argument('--'+n,required=True)
a=P.parse_args();R=Path(__file__).resolve().parents[1]
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
B=Path(a.build);b=read(B/'result.json')
assert b['BuildPass'] and b['ExistingConstraintsMet'] and b['InputsUnchanged'] and b['Version']=='M3-01 3.0'
for item in read(B/'inputs.json'):
 assert sha(item['Source'])==item['SHA256'].upper(),item['Source']
 assert sha(B/item['RelativePath'])==item['SnapshotSHA256'].upper()
assert sha(b['Release'])==b['SHA256']
dirs={n:Path(getattr(a,n)) for n in ['full','unit','m2','vendor','processing']}
audit={}
for label,d in dirs.items():
 result=read(d/'result.json');assert result['Verdict']=='PASS',result
 differences=[]
 for name,h in read(d/'inputs.json').items():
  if sha(name)!=h.upper(): differences.append(name)
 # Existing M2 checks hash all RTL, including M3 files they never compile.
 # Only those explicitly unconsumed files may differ; M3 runs must be exact.
 allowed=[]
 if label in ['vendor','processing']:allowed=[R/'rtl/network/m3_net_core.v',R/'rtl/network/m3_right_store.v',R/'rtl/display/m3_osd.v',R/'rtl/display/m3_text.v']
 assert all(Path(n) in allowed for n in differences),differences
 audit[label]={'ConsumedInputsUnchanged':True,'UnusedManifestDifferences':differences,'Directory':str(d.resolve())}
address=read(R/'reports/M3_01_address.json');assert address['Verdict']=='PASS'
for n,h in address['Inputs'].items():assert sha(R/n)==h.upper()
D=R/'release/FPGA_GSV1_M3_01_3_0';assert not D.exists(),'Preserve existing releases'
D.mkdir();bit=D/'FPGA_GSV1_M3_01_3_0_NETWORK_CONTROL.sbit';shutil.copy2(b['Release'],bit)
for folder,ext in [('report_timing','.rtr'),('device_map','.dmr'),('place_route','.prr')]:
 shutil.copy2(B/folder/('fpga_gsv1_top'+ext),D/(folder+ext))
shutil.copy2(B/'inputs.json',D/'build_inputs.json')
shutil.copy2(B/'result.json',D/'build_result.json')
shutil.copy2(R/'reports/M3_01_address.json',D/'address_check.json')
shutil.copy2(R/'reports/M3_01_pc_pacing.json',D/'pc_pacing.json')
shutil.copy2(R/'reports/M3_01_build_metrics.json',D/'build_metrics.json')
shutil.copy2(R/'reports/M3_01_osd_sim.png',D/'osd_sim.png')
shutil.copytree(R/'reports/M3_01_timeout_before',D/'verification/timeout_before',ignore=shutil.ignore_patterns('*.vvp'))
shutil.copytree(R/'reports/M3_01_right_owner_before',D/'verification/right_owner_before',ignore=shutil.ignore_patterns('*.vvp'))
for label,d in dirs.items():
 target=D/'verification'/label;target.mkdir(parents=True)
 for f in d.iterdir():
  if f.suffix in ['.log','.json']:shutil.copy2(f,target/f.name)
S=D/'source';S.mkdir()
for folder in ['rtl','vendor','constraints']:shutil.copytree(B/folder,S/folder)
for folder in ['scripts','sim','tools/m3']:shutil.copytree(R/folder,S/folder,ignore=shutil.ignore_patterns('__pycache__'))
shutil.copy2(B/'flow.tcl',S/'flow.tcl')
shutil.copy2(B/'build.pds',S/'FPGA_GSV1_M3_01.pds')
shutil.copy2(B/'build.pds',R/'FPGA_GSV1_M3_01.pds')
(S/'reports').mkdir();shutil.copy2(R/'reports/M2_01_edid.bin',S/'reports/M2_01_edid.bin')
(S/'docs').mkdir()
for source,name in [('docs/M3_01_board_test.md','USER_TEST.md'),('docs/M3_01_protocol.md','PROTOCOL.md'),('reports/M3_01_delivery.md','DELIVERY.md')]:
 shutil.copy2(R/source,D/name)
 shutil.copy2(R/source,S/source)
instant=datetime.datetime.fromisoformat(re.sub(r'(\.\d{6})\d+',r'\1',b['GeneratedTime']).replace('Z','+00:00'))
record=dict(Version=b['Version'],Bitstream=str(bit.resolve()),SHA256=b['SHA256'],
 GeneratedUtc=instant.isoformat(),GeneratedShanghai=instant.astimezone(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
 Build=str(B.resolve()),Verification=audit,BuildPass=True,ConsumedInputsUnchanged=True,
 Programmed=False,BoardVerified=False,ExternalIoTimingSignoff=False,MeasuredHardwareFps=None)
(D/'release.json').write_text(json.dumps(record,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps(record,indent=2,ensure_ascii=False))
