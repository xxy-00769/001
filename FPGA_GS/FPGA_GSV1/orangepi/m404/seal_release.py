import json,hashlib,urllib.request,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1];here=root/'m404'
old=json.loads((root/'m403/evidence/sealed_release.json').read_text())
preserved=[]
for row in old['files']+old['baseline']:
 p=root/row['path'];actual=hashlib.sha256(p.read_bytes()).hexdigest()
 preserved.append(dict(path=row['path'],sha256=actual,unchanged=actual==row['sha256']))
artifacts=[]
for row in json.loads((here/'model_manifest.json').read_text())['artifacts']:
 p=here/row['remote_path'];actual=hashlib.sha256(p.read_bytes()).hexdigest()
 artifacts.append(dict(path=str(p.relative_to(root)),sha256=actual,matches=actual==row['sha256']))
status=json.load(urllib.request.urlopen('http://127.0.0.1:8080/status.json'));status.pop('control_token',None)
record=json.loads((here/'state/demo_service.json').read_text());pid=record['identity']['pid']
libs=[x.strip() for x in Path(f'/proc/{pid}/maps').read_text().splitlines() if 'librknn' in x]
code=[]
for name in ['demo.py','detector.py','overlay.py','index.html','demo_ops.py']:
 p=here/name;code.append(dict(path=str(p.relative_to(root)),sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
result=dict(release='M4-04-r1',remote_dir=str(root),pid=pid,preserved=preserved,models=artifacts,code=code,loaded_libraries=libs,status=status,
 udp_sockets=subprocess.check_output(['ss','-lunp'],text=True),backup=str(here/'backup/m403_before_m404.tgz'))
(here/'evidence/release_validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
assert all(x['unchanged'] for x in preserved)
assert all(x['matches'] for x in artifacts)
assert status['release']=='M4-04-r1' and status['detection']['backend']=='RKNN/NPU'
print('preserved',len(preserved),'files; all model hashes match; real backend',status['detection']['backend'],'pid',pid)
