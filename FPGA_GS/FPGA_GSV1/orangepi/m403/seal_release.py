"""Record hashes and current rule checks for this additive offline delivery."""
import hashlib,json,subprocess,sys,tarfile
from pathlib import Path
R=Path(__file__).resolve().parents[1]
manifest=json.loads((R/'m403/deployment_manifest.json').read_text(encoding='utf-8-sig'))
for x in manifest:
 x['actual_sha256']=hashlib.sha256((R/x['path']).read_bytes()).hexdigest();x['matches']=x['sha256']==x['actual_sha256']
assert all(x['matches'] for x in manifest)
baseline=[]
with tarfile.open(R/'m403/backup_before_demo/m402_reconnect_before.tgz') as archive:
 for m in archive.getmembers():
  if m.isfile():
   a=hashlib.sha256(archive.extractfile(m).read()).hexdigest();b=hashlib.sha256((R/m.name).read_bytes()).hexdigest();baseline.append(dict(path=m.name,unchanged=a==b,sha256=b))
assert all(x['unchanged'] for x in baseline)
run=subprocess.run([sys.executable,str(R/'m403/test_driving.py')],capture_output=True,text=True);assert run.returncode==0
out=dict(release='M4-03-demo-r1',files=manifest,baseline=baseline,rules=dict(returncode=run.returncode,output=run.stdout+run.stderr),network_sockets=subprocess.check_output(['ss','-lntup'],text=True),note='No service restart, system setting or network mutation in this check')
(R/'m403/evidence/sealed_release.json').write_text(json.dumps(out,ensure_ascii=False,indent=2));print('release hashes match; LIVE baseline unchanged; rule checks passed')
