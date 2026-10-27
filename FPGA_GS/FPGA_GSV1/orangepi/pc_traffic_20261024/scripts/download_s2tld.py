import urllib.request,json,urllib.parse,hashlib,time
from pathlib import Path
root=Path(__file__).resolve().parents[1]
items=json.loads((root/'sources/hf_s2tld_tree.txt').read_text())
f=next(x for x in items if x['path'].endswith('.zip') and '1080' in x['path'])
u='https://huggingface.co/datasets/yangxue/S2TLD/resolve/82f6494de63f6412b8112c8413c3559723dd3cfd/'+urllib.parse.quote(f['path'])+'?download=true'
print(repr(f['path']),u,flush=True)
p=root/'data/s2tld_1080.zip';n=0;t=time.time()
with urllib.request.urlopen(u,timeout=90) as r,p.open('wb') as out:
 while True:
  b=r.read(4*1024*1024)
  if not b:break
  out.write(b);n+=len(b)
  if n%(32*1024*1024)==0:print('download MB',n//1048576,round(time.time()-t,1),flush=True)
h=hashlib.sha256(p.read_bytes()).hexdigest();assert h==f['lfs']['oid'],(h,f['lfs']['oid'])
(root/'data/archive_provenance.json').write_text(json.dumps({'url':u,'revision':'82f6494de63f6412b8112c8413c3559723dd3cfd','bytes':n,'sha256':h,'license':'Apache-2.0 official author mirror linked by upstream README','license_evidence':['sources/hf_s2tld_readme.txt','sources/s2tld_readme.txt'],'note':'Raw source annotations are unreviewed; not training ground truth.'},indent=2),encoding='utf-8')
print('verified',n,h,flush=True)
