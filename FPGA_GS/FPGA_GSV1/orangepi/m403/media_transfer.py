"""Content-verified media transfer helper. Does not decode, label or modify originals."""
import argparse,base64,hashlib,json,shutil,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
NAMES={'SC_BT.mp4','SC_BT2.mp4','SC_YJ.mp4','SC_YJ2.mp4'}
def digest(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for block in iter(lambda:f.read(4*1024*1024),b''):h.update(block)
 return h.hexdigest()
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('action',choices=['inspect','commit']);p.add_argument('--manifest',required=True);p.add_argument('--name');a=p.parse_args()
 rows=json.loads(base64.b64decode(a.manifest));assert {r['name'] for r in rows}==NAMES
 media=ROOT/'media';media.mkdir(exist_ok=True)
 if a.action=='inspect':
  result=[]
  for r in rows:
   f=media/r['name'];result.append(dict(name=r['name'],exists=f.exists(),bytes=f.stat().st_size if f.exists() else None,sha256=digest(f) if f.exists() else None))
  print(json.dumps(dict(free_bytes=shutil.disk_usage(media).free,files=result)))
 else:
  assert a.name in NAMES;r=next(x for x in rows if x['name']==a.name);temp=media/('.'+a.name+'.m403_upload');dest=media/a.name
  assert temp.stat().st_size==r['bytes'] and digest(temp)==r['sha256'],'上传文件SHA256不一致，未替换原片'
  retained=None
  if dest.exists():
   retained=media/(a.name+'.retained_'+time.strftime('%Y%m%d_%H%M%S'));assert not retained.exists();dest.rename(retained)
  temp.rename(dest);print(json.dumps(dict(ok=True,path=str(dest),sha256=r['sha256'],retained=str(retained) if retained else None)))
