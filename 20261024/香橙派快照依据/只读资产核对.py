"""Handoff-only inventory: remote reads over verified SSH; writes only this local folder.
No deployment, model load, video decode, performance sampling, service/network mutation.
Not an atomic backup. Large media hashes reuse dated M4-03 manifests.
"""
from pathlib import Path
import subprocess,json,os,hashlib,datetime,csv
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
PI=ROOT/'orangepi'
C=json.loads((PI/'oneclick/config.json').read_text(encoding='utf-8-sig'))
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
REMOTE=r'''
import os,sys,json,hashlib,subprocess,datetime,urllib.request
from pathlib import Path
R=Path('/home/orangepi/fpga_gs_m401_v0_1_2_20261021')
def stamp():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def cmd(a):
 try:
  p=subprocess.run(a,capture_output=True,text=True,timeout=20);return dict(code=p.returncode,out=p.stdout.strip(),err=p.stderr.strip())
 except Exception as e:return dict(error=str(e))
def digest(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def meta(p,hash_it=False):
 try:
  s=p.stat();v=dict(path=str(p),bytes=s.st_size,mtime_ns=s.st_mtime_ns,mtime_utc=datetime.datetime.fromtimestamp(s.st_mtime,datetime.timezone.utc).isoformat())
  if hash_it:
   v['sha256']=digest(p);t=p.stat();v['stable_during_hash']=(s.st_size,s.st_mtime_ns)==(t.st_size,t.st_mtime_ns)
  return v
 except Exception as e:return dict(path=str(p),error=str(e))
def scrub(x):
 if isinstance(x,dict):return {k:scrub(v)for k,v in x.items()if not any(w in k.lower()for w in ['token','password','secret','private_key'])}
 if isinstance(x,list):return [scrub(v)for v in x]
 return x
out=dict(start_utc=stamp(),root=str(R),host=cmd(['uname','-a']),os_release=Path('/etc/os-release').read_text(),boot_id=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),uptime=Path('/proc/uptime').read_text().strip(),disk=cmd(['df','-B1',str(R)]),ram=Path('/proc/meminfo').read_text().splitlines()[:4])
out['project_processes']=[]
for p in Path('/proc').glob('[0-9]*'):
 try:
  args=(p/'cmdline').read_bytes().replace(b'\0',b' ').decode(errors='replace')
  if str(R) in args or any(x in args for x in ['m406/demo.py','m405r2/demo.py','main.py --mode LIVE_FRONT']):
   if 'bash -c' not in args and int(p.name)!=os.getpid():out['project_processes'].append(dict(pid=int(p.name),args=args,cwd=os.readlink(p/'cwd'),stat=(p/'stat').read_text()))
 except OSError:pass
out['listeners_8080_50000']=[s for s in cmd(['ss','-lntup']).get('out','').splitlines()if ':8080 ' in s or ':50000 ' in s]
try:
 with urllib.request.urlopen('http://127.0.0.1:8080/status.json',timeout=2)as f:out['status_once']=scrub(json.load(f))
except Exception as e:out['status_once']=dict(unavailable=str(e))
out['network_readonly']=dict(ip=cmd(['ip','-j','address','show','dev','eth0']),route=cmd(['ip','-j','route','get','192.168.60.2']),rmem_max=Path('/proc/sys/net/core/rmem_max').read_text().strip())
for n in ['carrier','speed','operstate']:
 try:out['network_readonly'][n]=Path('/sys/class/net/eth0/'+n).read_text().strip()
 except OSError as e:out['network_readonly'][n]='UNKNOWN: '+str(e)
skip={'evidence','runs','state','__pycache__','build_vendor','.git'}
ext={'.py','.html','.json','.ps1','.cmd','.md','.txt','.rknn','.onnx','.pt','.whl','.so','.tgz','.gz','.zip','.ttc','.ttf','.sha256'}
out['assets']=[];out['mutable_log_stats']=[]
for base,dirs,files in os.walk(R):
 dirs[:]=[d for d in dirs if d not in skip and not d.startswith('.venv') and d!='media']
 for n in files:
  p=Path(base)/n
  if p.suffix.lower() in ext:
   v=meta(p,True);v['relative']=str(p.relative_to(R));out['assets'].append(v)
for p in R.glob('*/state/*.log'):out['mutable_log_stats'].append(meta(p))
for p in (R/'runs').glob('*/events*.jsonl'):out['mutable_log_stats'].append(meta(p))
out['media']=[]
for p in list((R/'media').glob('*'))+list(R.glob('1021*')):
 if p.is_file():out['media'].append(meta(p))
out['old_roots']=[dict(path=str(p),exists=p.exists())for p in [R.parent/'fpga_gs_m401_20261021',R.parent/'fpga_gs_m401_v0_1_1_20261021']]
out['fonts']=[meta(p,True)for p in [Path('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'),Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')]if p.exists()]
out['deps']={}
query="import sys,json,importlib.metadata as m;print(json.dumps(dict(python=sys.version,executable=sys.executable,packages=sorted([dict(name=d.metadata.get('Name'),version=d.version)for d in m.distributions()],key=lambda x:str(x['name'])))))"
for n in ['.venv','.venv404','.venv405build']:
 p=R/n;v=cmd([str(p/'bin/python'),'-B','-c',query]);out['deps'][n]=json.loads(v['out'])if v.get('code')==0 else v
 if (p/'pyvenv.cfg').exists():out['deps'][n]['pyvenv_cfg']=(p/'pyvenv.cfg').read_text()
out['tool_versions']={n:cmd(a)for n,a in [('ffmpeg',['ffmpeg','-version']),('ffprobe',['ffprobe','-version']),('gcc',['gcc','--version']),('runtime',['ldconfig','-p']),('npu_driver',['modinfo','rknpu'])]}
out['runtime_libs']=[meta(p,True)for p in [Path('/usr/lib/librknnrt.so'),Path('/usr/lib/aarch64-linux-gnu/librknnrt.so')]if p.exists()]
out['npu_version']=cmd(['cat','/sys/kernel/debug/rknpu/version'])
out['project_config']={}
for rel in ['oneclick/config.json','endpoints.contract.json','scene.example.json','operator_v1/state/receive_buffer_sysctl.json','m403/scenes.json']:
 p=R/rel
 if p.exists():
  try:out['project_config'][rel]=scrub(json.loads(p.read_text()))
  except Exception as e:out['project_config'][rel]=dict(error=str(e))
out['end_utc']=stamp();print(json.dumps(out,ensure_ascii=False))
'''
started=now()
remote=subprocess.run(['ssh','-p',str(C['ssh_port']),'-o','StrictHostKeyChecking=yes','-o','ConnectTimeout=10',C['ssh_user']+'@'+C['ssh_host'],'python3 -B -'],input=REMOTE,text=True,encoding='utf8',capture_output=True,timeout=180)
if remote.returncode:raise RuntimeError(remote.stderr)
r=json.loads(remote.stdout);(HERE/'remote_readonly.json').write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf8')
skip={'evidence','runs','reports','state','__pycache__','node_modules','build_vendor','pc_traffic_20261024'}
assets=[]
for base,dirs,files in os.walk(PI):
 dirs[:]=[d for d in dirs if d not in skip and not d.startswith('.venv')]
 for n in files:
  p=Path(base)/n
  if p.suffix.lower()in {'.py','.html','.json','.ps1','.cmd','.md','.txt','.rknn','.onnx','.pt','.whl','.so','.tgz','.gz','.zip','.ttc','.ttf','.sha256'}:
   s=p.stat();v=dict(relative=p.relative_to(PI).as_posix(),bytes=s.st_size,mtime_ns=s.st_mtime_ns,sha256=sha(p));t=p.stat();v['stable_during_hash']=(s.st_size,s.st_mtime_ns)==(t.st_size,t.st_mtime_ns);assets.append(v)
lookup={x['relative']:x for x in assets};comparison=[]
for x in r['assets']:
 y=lookup.get(x['relative']);comparison.append(dict(remote_relative=x['relative'],remote_bytes=x.get('bytes'),remote_sha256=x.get('sha256'),local_relative=x['relative'] if y else '',match=(y['sha256']==x.get('sha256'))if y else None,remote_stable=x.get('stable_during_hash')))
with (HERE/'local_remote_comparison.tsv').open('w',encoding='utf-8-sig',newline='')as f:
 w=csv.DictWriter(f,fieldnames=list(comparison[0]),delimiter='\t');w.writeheader();w.writerows(comparison)
local_media=[]
for p in (ROOT.parent/'SC').glob('*.mp4'):
 if p.name in ['SC_BT.mp4','SC_BT2.mp4','SC_YJ.mp4','SC_YJ2.mp4','1021.mp4']:
  s=p.stat();local_media.append(dict(path=str(p),bytes=s.st_size,mtime_ns=s.st_mtime_ns,hash_policy='Reuse orangepi/m403/media_manifest.json; not rehashed in this handoff'))
out=dict(start_utc=started,end_utc=now(),root=str(ROOT),config=C,assets=assets,local_media=local_media,policy='Selected source/config/model hash observation, non-atomic, no state/log payload or credentials copied; source versions remain in place')
(HERE/'local_readonly.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(dict(remote_assets=len(r['assets']),local_assets=len(assets),same=sum(x['match']is True for x in comparison),different=[x['remote_relative']for x in comparison if x['match']is False],remote_only=len([x for x in comparison if x['match']is None]),processes=r['project_processes'],listeners=r['listeners_8080_50000'],network=r['network_readonly'],range=[started,now()]),ensure_ascii=False,indent=2))
