"""Freeze a successful M3-06 implementation without touching root WIP RTL."""
from pathlib import Path
import datetime, hashlib, json, re, shutil, sys, zipfile

R = Path(__file__).resolve().parents[1]
ROOT = R.parents[1]
B = Path(sys.argv[1]).resolve()
build = json.loads((B/'result.json').read_text(encoding='utf-8-sig'))
assert build['BuildPass'] and build['ExistingConstraintsMet'] and build['InputsUnchanged'], build
timing = (B/'report_timing/fpga_gsv1_top.rtr').read_text()
assert 'Design Summary : All Constraints Met.' in timing
assert re.search(r'eth2_async[^\n]*eth2_rxc\|[^\n]*CLKDIVOUT', timing), 'Missing related clock group'
assert re.search(r'CLKDIVOUT_Inferred\s*\n\s*eth2_rxc\s+[-\d.]', timing), 'Missing related /2 -> MAC STA'
for item in json.loads((B/'inputs.json').read_text(encoding='utf-8-sig')):
    assert hashlib.sha256(Path(item['Source']).read_bytes()).hexdigest().upper() == item['SHA256']

checks = {'full':'sim_m36_full_15_20261021_201942', 'host':'m36_host', 'rgmii':'m36_reproduce_rgmii'}
for case, folder in checks.items():
    res=json.loads((R/'reports'/folder/'result.json').read_text(encoding='utf-8-sig'))
    assert res['Verdict']=='PASS', (case,res)
    for file,h in res.get('InputSHA256',{}).items():
        assert hashlib.sha256((R/file).read_bytes()).hexdigest()==h
old_inputs=json.loads((R/'reports/m36_units/inputs.json').read_text())
for file,h in old_inputs.items():
    if 'rgmii' not in file:
        assert hashlib.sha256(Path(file).read_bytes()).hexdigest()==h

release=ROOT/'release/FPGA_GSV1_M3_06_3_5'
assert not release.exists(), 'Never overwrite a release'
release.mkdir()
source=release/'source'; source.mkdir()
for folder in ['rtl','vendor','constraints','config','tools','scripts','sim','docs']:
    shutil.copytree(R/folder,source/folder,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
for file in ['flow.tcl','README.md']:
    shutil.copy2(R/file,source/file)
shutil.copy2(B/'build.pds',source/'FPGA_GSV1_M3_06.pds')
assert 'm36_phy2.v' in (source/'FPGA_GSV1_M3_06.pds').read_text()
assert 'm36_rgmii_interface.v' in (source/'FPGA_GSV1_M3_06.pds').read_text()
bit=release/'FPGA_GSV1_M3_06_3_5_DUAL_ETH_HDMI_1080P60.sbit'
shutil.copy2(B/'generate_bitstream/fpga_gsv1_top.sbit',bit)

e=release/'evidence'; e.mkdir()
for folder in checks.values():
    d=e/folder;d.mkdir()
    for file in (R/'reports'/folder).iterdir():
        if file.suffix in ('.json','.log','.v'):shutil.copy2(file,d/file.name)
shutil.copytree(R/'reports/m36_units',e/'m36_units')
probe=e/'io_probe';probe.mkdir()
for file in ['io.v','top.v','flow.tcl','io.fdc','probe_ides4_related_group.log']:
    shutil.copy2(R/'reports/m36_io_probe'/file,probe/file)
shutil.copy2(R/'reports/m36_io_probe/report_timing/io_probe.rtr',probe/'io_probe.rtr')
for file in ['M3_06_baseline_diff.json','M3_06_network_readonly.json']:
    shutil.copy2(R/'reports'/file,e/file)
shutil.copy2(ROOT/'reports/M3_06_baseline.json',e/'M3_06_baseline.json')
for rel in ['pds_console.log','result.json','inputs.json','report_timing/fpga_gsv1_top.rtr','device_map/fpga_gsv1_top_dmr.prt']:
    dest=e/'build'/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(B/rel,dest)

log=(B/'pds_console.log').read_text(errors='replace')
def resource(label,first=False):
    values=re.findall(r'\|\s*'+re.escape(label)+r'\s*\|\s*([\d.]+)',log)
    assert values,label
    return float(values[0] if first else values[-1])
resources={n:resource(l) for n,l in {'DRM':'Use of DRM','PLL':'Use of PLL','APM':'Use of APM','CLMA':'Use of CLMA','CLMS':'Use of CLMS'}.items()}
resources['FF']=resource('FF',True)
resources['MappedLUT']=resource('LUT',True)
resources['RoutedLUT']=sum(map(float,re.findall(r'\|\s+LUT\s+\|\s*([\d.]+)',log)[-2:]))
resources['CLBPercent']=100*(resources['CLMA']+resources['CLMS'])/10700
slacks={}
for m in re.finditer(r'((?:Setup|Hold|Recovery|Removal) Summary\((?:Slow|Fast) Corner\):)(.*?)(?:={10,})',timing,re.S):
    vals=re.findall(r'\s(-?\d+\.\d+)\s+-?\d+\.\d+\s+\d+\s+\d+\s*$',m[2],re.M)
    if vals:slacks[m[1]]=min(map(float,vals))
assert len(slacks)>=4,slacks
utc=datetime.datetime.fromtimestamp(bit.stat().st_mtime,datetime.timezone.utc)
record=dict(Version='M3-06 3.5',Bitstream=str(bit),SHA256=hashlib.sha256(bit.read_bytes()).hexdigest().upper(),
    GeneratedUtc=utc.isoformat(),GeneratedShanghai=utc.astimezone(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
    Build=str(B),BuildPass=True,ExistingConstraintsMet=True,InputsUnchanged=True,Programmed=False,BoardMeasured=False,
    ExternalIoTimingSignoff=False,Resources=resources,MinSlackNs=slacks,
    Baseline='Published M3-04 3.3 source; user confirmed 15fps',
    Endpoints=json.loads((R/'config/m3_endpoints.json').read_text()),
    RequestedFPS=dict(Right=15,FrontRaw=5),HardwareFPSMeasured=False,AdditionalUploadReader=False,
    Output=dict(Width=1920,Height=1080,Fps=60,PixelHz=148500000,HTotal=2200,VTotal=1125,VIC=16),
    ContractSHA256=hashlib.sha256((R/'docs/M4_link_contract.md').read_bytes()).hexdigest(),
    ProtocolSHA256=hashlib.sha256((R/'tools/m3/protocol.py').read_bytes()).hexdigest(),
    Verification=checks,PerfSimulationProcessingBypass=True,BuildProcessingEnable=True,
    KnownPending=['Dual PHY hardware and FPS acceptance','External TX/PCB timing and electrical signoff','Prior rear green-dot feedback, not changed'])
(release/'release.json').write_text(json.dumps(record,indent=2,ensure_ascii=False),encoding='utf-8')
manifest={str(p.relative_to(source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in source.rglob('*') if p.is_file()}
(release/'source_sha256.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(json.dumps(record,indent=2,ensure_ascii=False))
