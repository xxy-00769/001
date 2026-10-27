"""Documentation-only local inventory. No build, device, network or serial operations."""
from pathlib import Path
import csv,json,hashlib,re,datetime,xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[3];out=Path(__file__).parent
t0=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat()
def rel(p):return p.relative_to(root).as_posix()
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def tsv(name,rows,fields):
 with (out/name).open('w',encoding='utf-8-sig',newline='') as f:
  w=csv.DictWriter(f,fieldnames=fields,delimiter='\t',extrasaction='ignore');w.writeheader();w.writerows(rows)
def sum_map(d):
 for n in ('SHA256SUMS','SHA256SUMS.txt'):
  p=d/n
  if p.exists():
   m={}
   for l in p.read_text(encoding='utf-8-sig').splitlines():
    a=re.match(r'^([0-9a-fA-F]{64})\s+\*?(.*)$',l)
    if a:m[a[2].replace('\\','/').lstrip('./')]=a[1].lower()
   return p,m
 return None,{}
versions=[];early=[]
for d in sorted((root/'release').iterdir()):
 if not d.is_dir():continue
 meta=next((p for p in [d/'artifact.json',d/'release.json',d/'reports/experiment_summary.json'] if p.exists()),None)
 r=load(meta) if meta else {};bit=next(d.glob('*.sbit'),None)
 mp,sm=sum_map(d)
 sha=r.get('sha256',r.get('SHA256','')) or (sm.get(bit.name,'') if bit else '')
 generated=next((r[k] for k in ['generated_Asia_Shanghai','generated_local_time','generated_time_shanghai','generated_local','GeneratedShanghai','generated_time','GeneratedTime','GeneratedUtc'] if k in r),'UNKNOWN')
 build=next((r[k] for k in ['build','Build','build_directory','RunDirectory'] if isinstance(r.get(k),str)),'')
 if build:
  norm=build.replace('\\','/');pos=norm.find('FPGA_GSV1/');bp=root/norm[pos+len('FPGA_GSV1/'):] if pos>=0 else Path(norm)
 else:bp=None
 versions.append(dict(Release=rel(d),Bitstream=rel(bit) if bit else 'NONE',Bytes=bit.stat().st_size if bit else '',SHA256_existing=sha or 'UNKNOWN',HashEvidence=rel(meta) if meta else (rel(mp) if mp else 'UNKNOWN'),Generated_recorded=generated,SourceExists=(d/'source').exists(),BuildSnapshot=rel(bp) if bp and bp.is_relative_to(root) else build,BuildSnapshotExists=bp.exists() if bp else 'UNKNOWN',DeclaredBuildPass=r.get('build_pass',r.get('BuildPass','UNKNOWN'))))
 if not (d/'source').exists():
  early.append(dict(Release=rel(d),BuildSnapshot=rel(bp) if bp and bp.is_relative_to(root) else build,Exists=bp.exists() if bp else False,Required='rtl/ vendor/ constraints/ config/ flow.tcl; inputs.json/result.json/build.tcl and release build_inputs; matching scripts/sim must retain',Note='Release has no source directory. Historical source closure must be copied from matching build.'))
tsv('FPGA发布版本索引.tsv',versions,list(versions[0]))
tsv('FPGA早期源码补复制.tsv',early,list(early[0]))
selected=['FPGA_GSV1_CAM0_OV5640_3_5_9_READBACK','FPGA_GSV1_CAM1_OV3660_3_5_8_ROTATE25_CANDIDATE','FPGA_GSV1_M3_06_3_5_5_TXDET1_CANDIDATE','FPGA_GSV1_NET2_BASELINE_E1','FPGA_GSV1_CAM0_OV5640_3_5_9_MOTION_CANDIDATE']
frozen=[];missing=[]
for n in selected:
 d=root/'release'/n;mp,sm=sum_map(d)
 for sub in ['source','tools']:
  if not (d/sub).exists():continue
  for p in sorted((d/sub).rglob('*')):
   if not p.is_file() or '__pycache__' in p.parts:continue
   st=p.stat();key=p.relative_to(d).as_posix();sha=sm.get(key,'UNKNOWN')
   if sha=='UNKNOWN':missing.append(rel(p))
   frozen.append(dict(Baseline=n,Path=rel(p),Bytes=st.st_size,SHA256=sha,HashOrigin=rel(mp) if mp else 'UNKNOWN',HashMethod='reused existing release manifest; not recomputed',ObservedAt=t0,Modified_ns=st.st_mtime_ns,Classification='ARCHIVE_UNTESTED' if 'MOTION' in n else ('CURRENT_BOARD_SOURCE' if 'READBACK' in n else 'REFERENCE_ROLLBACK')))
tsv('FPGA冻结发布输入清单.tsv',frozen,list(frozen[0]))
# Select one active work snapshot, not all history/build outputs.
wroot=root/'work/CAM0_motion';work=[];before={}
for sub in ['rtl','vendor','constraints','config','scripts','sim','tools']:
 for p in sorted((wroot/sub).rglob('*')):
  if p.is_file() and '__pycache__' not in p.parts and 'reports' not in p.relative_to(wroot).parts and p.suffix not in ('.vvp','.pyc'):
   before[p]=(p.stat().st_size,p.stat().st_mtime_ns)
for p in [wroot/'flow.tcl']:
 before[p]=(p.stat().st_size,p.stat().st_mtime_ns)
for p,(size,mt) in before.items():
 sha=hashlib.sha256(p.read_bytes()).hexdigest();s=p.stat();stable=(size,mt)==(s.st_size,s.st_mtime_ns)
 work.append(dict(Path=rel(p),Bytes=size,SHA256=sha,ObservedAt=t0,Modified_ns=mt,ReadStable=stable,State='ARCHIVED_MOTION_WORK_NOT_CURRENT_BOARD',HashMethod='new SHA256 of selected work input only'))
changed=[]
for p,v in before.items():
 if (p.stat().st_size,p.stat().st_mtime_ns)!=v:changed.append(rel(p))
for r in work:
 if r['Path'] in changed:r['ReadStable']=False
 t=None
tsv('FPGA当前work输入快照.tsv',work,list(work[0]))
# Resolve actual R0 Tcl/IDF/include source closure, existence-only. No tools run.
b=root/'release/FPGA_GSV1_CAM0_OV5640_3_5_9_READBACK/source';closure={};issues=[]
def add(p,kind,via):
 key=rel(p) if p.is_relative_to(root) else str(p)
 if key in closure:return
 closure[key]=dict(Path=key,Kind=kind,RequiredBy=via,Exists=p.exists(),Bytes=p.stat().st_size if p.exists() else '',SHA256_existing=next((r['SHA256'] for r in frozen if r['Path']==key),'UNKNOWN'))
 if not p.exists():issues.append(key);return
 if p.suffix=='.idf':
  x=ET.parse(p).getroot()
  for e in x.findall('.//source/file'):
   fn=e.get('pathname')
   if fn:add(p.parent/fn,'IDF source',key)
 if p.suffix in ('.v','.vh','.sv'):
  for name in re.findall(r'`include\s+"([^"]+)"',p.read_text(encoding='utf-8-sig',errors='replace')):
   options=[p.parent/name,b/name];target=next((q for q in options if q.exists()),None)
   if target is None:
    a=list((b/'rtl').rglob(name));target=a[0] if len(a)==1 else p.parent/name
   add(target,'Verilog include',key)
add(b/'flow.tcl','PDS flow','primary root')
s=(b/'flow.tcl').read_text()
for typ,name in re.findall(r'add_(design|constraint)\s+"([^"]+)"',s):add(b/name,'Tcl '+typ,'source/flow.tcl')
for name in ['config/m3_endpoints.json','scripts/build_cam0.ps1','scripts/configure_m36_endpoints.py']:
 add(b/name,'entry/generation dependency','build_cam0.ps1')
tsv('FPGA_R0构建依赖闭包.tsv',list(closure.values()),list(next(iter(closure.values()))))
summary=dict(StartedAt=t0,FinishedAt=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),ProductionMutations=False,HardwareOrNetworkOperations=False,BuildOrTestsRun=False,PublishedDirectories=len(versions),FrozenInputRows=len(frozen),PublishedHashReused=True,MissingPublishedHashes=missing,SelectedWorkRows=len(work),WorkInputsChangedDuringRead=changed,AtomicFilesystemSnapshot=False,SnapshotClaim='Frozen release manifest references plus per-file work read stability. No OS atomic snapshot/immutable source copy created.',PrimaryClosureRows=len(closure),PrimaryClosureMissing=issues,Primary='release/FPGA_GSV1_CAM0_OV5640_3_5_9_READBACK/source',CurrentWork='work/CAM0_motion is MOTION candidate, NOT original-exposure board source',GitAtProject=(root/'.git').exists())
(out/'FPGA交接只读核对.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(summary,ensure_ascii=False,indent=2))
