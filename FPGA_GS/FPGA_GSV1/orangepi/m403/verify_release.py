"""Directed additive-release validation; no LIVE startup, UDP, or system mutations."""
import base64,hashlib,io,json,os,socket,subprocess,sys,tarfile,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'m403'))
import demo_ops
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
cfg=json.loads((ROOT/'operator_v1/config.json').read_text());cfg['remote_dir']=str(ROOT)
backup=ROOT/'m403/backup_before_demo/m402_reconnect_before.tgz';baseline=[]
with tarfile.open(backup) as archive:
 for member in archive.getmembers():
  if not member.isfile():continue
  old=hashlib.sha256(archive.extractfile(member).read()).hexdigest();current=sha(ROOT/member.name)
  baseline.append(dict(path=member.name,backup_sha256=old,current_sha256=current,unchanged=old==current))
assert all(r['unchanged'] for r in baseline),'LIVE baseline changed'
result=dict(baseline=baseline)
# This test is only run after the owned demo was stopped. Bind our own temporary
# TCP listener: real port-conflict evidence, without terminating any other service.
with socket.socket() as listener,tempfile.TemporaryDirectory() as state:
 listener.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
 listener.bind(('127.0.0.1',int(cfg['web_port'])));listener.listen(1)
 conflict=demo_ops.start(cfg,Path(state));assert not conflict['ok'] and conflict.get('conflicts'),conflict
 result['foreign_port_refused']=conflict
result['rules']=subprocess.run([sys.executable,str(ROOT/'m403/test_driving.py')],capture_output=True,text=True).__dict__
assert result['rules']['returncode']==0
try:
 import cv2,numpy,PIL
 result['runtime']=dict(python=sys.version,opencv=cv2.__version__,numpy=numpy.__version__,pillow=PIL.__version__,cpu='RK3588S CPU',npu=False)
except ImportError:raise
(ROOT/'m403/evidence/release_checks.json').write_text(json.dumps(result,ensure_ascii=False,indent=2,default=str))
print(json.dumps(result,ensure_ascii=False,default=str))
