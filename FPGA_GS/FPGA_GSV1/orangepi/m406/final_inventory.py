import json,hashlib,subprocess,os,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
core=['demo.py','demo_ops.py','driving.py','overlay.py','road.py','lane_semantics.py','index.html']
backup=ROOT/'m406/backup';backup.mkdir(exist_ok=True)
old=[str(Path('m405r2')/n)for n in core]
archive=backup/'m405r2_preserved_source.tar.gz'
if not archive.exists():subprocess.run(['tar','-czf',str(archive),*old],cwd=ROOT,check=True)
media=[dict(name=p.name,bytes=p.stat().st_size)for p in sorted((ROOT/'media').glob('SC_*.mp4'))]
files={}
for version,names in [('m405r2',core),('m406',core+['traffic.py','yolov8s.pt','yolov8s640.onnx','yolov8s640_fp16.rknn','tlony.pt','tlony640_fp16.rknn'])]:
 for n in names:
  p=ROOT/version/n;files[str(p.relative_to(ROOT))]=dict(bytes=p.stat().st_size,sha256=digest(p))
import urllib.request
status=json.load(urllib.request.urlopen('http://127.0.0.1:8080/status.json',timeout=3));status.pop('control_token',None)
processes=subprocess.check_output(['ps','-eo','pid,args'],text=True)
service=[x for x in processes.splitlines() if 'm406/demo.py' in x and not 'final_inventory' in x]
ports=subprocess.check_output(['ss','-lntup'],text=True)
import cv2,numpy as np,PIL,sys,importlib.metadata
try:rknn_version=importlib.metadata.version('rknn-toolkit-lite2')
except importlib.metadata.PackageNotFoundError:rknn_version='unknown'
result=dict(at=time.strftime('%Y-%m-%d %H:%M:%S %z'),root=str(ROOT),files=files,media=media,service=service,ports_8080_or_50000=[x for x in ports.splitlines()if ':8080 ' in x or ':50000 ' in x],status=status,backup=str(archive),backup_sha256=digest(archive),runtime=dict(python=sys.version,executable=sys.executable,opencv=cv2.__version__,numpy=np.__version__,pillow=PIL.__version__,rknn_lite=rknn_version))
(ROOT/'m406/evidence/remote_inventory.json').write_text(json.dumps(result,ensure_ascii=False,indent=2));print(json.dumps(dict(root=str(ROOT),service=service,release=status['release'],error=status['error'],media=media),ensure_ascii=False))
