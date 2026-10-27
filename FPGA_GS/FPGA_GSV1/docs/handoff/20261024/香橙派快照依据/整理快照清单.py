"""Local-only derivation of portable handoff tables; never connects to the board."""
from pathlib import Path
import json,csv,hashlib,datetime
H=Path(__file__).resolve().parent;ROOT=H.parents[3]
r=json.loads((H/'remote_readonly.json').read_text(encoding='utf8'))
l=json.loads((H/'local_readonly.json').read_text(encoding='utf8'))
s=json.loads((H/'supplement.json').read_text(encoding='utf8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
for m in l['local_media']:
 if Path(m['path']).name=='1021.mp4':m['hash_policy']='Current same-named file has changed size since old DELIVERY; no current SHA asserted; not one of the four manifest originals'
(H/'local_readonly.json').write_text(json.dumps(l,ensure_ascii=False,indent=2),encoding='utf8')
byhash={}
for a in l['assets']:byhash.setdefault(a['sha256'],[]).append('orangepi/'+a['relative'])
rows=[]
for a in r['assets']:
 paths=byhash.get(a.get('sha256'),[])
 state='SAME_PATH'if 'orangepi/'+a['relative']in paths else 'SAME_CONTENT_ALIAS'if paths else 'REMOTE_ONLY_OR_DIFFERENT'
 rows.append(dict(remote='R/'+a['relative'],bytes=a.get('bytes'),sha256=a.get('sha256'),hash_basis='read-only hash '+r['start_utc'],local=' | '.join(paths),state=state))
for a in s['files']:
 p=ROOT/'orangepi'/a['relative'];equal=p.exists()and sha(p)==a['sha256']
 rows.append(dict(remote='R/'+a['relative'],bytes=a['bytes'],sha256=a['sha256'],hash_basis='supplement read-only hash 2026-10-24',local='orangepi/'+a['relative']if equal else '',state='SAME_PATH'if equal else 'REMOTE_ONLY_OR_DIFFERENT'))
for a in r['fonts']+r['runtime_libs']:
 rows.append(dict(remote=a['path'],bytes=a['bytes'],sha256=a['sha256'],hash_basis='read-only hash '+r['start_utc'],local='',state='SYSTEM_REMOTE_ONLY'))
media=json.loads((ROOT/'orangepi/m403/media_manifest.json').read_text(encoding='utf8'))
for a in media:
 rows.append(dict(remote='R/media/'+a['name'],bytes=a['bytes'],sha256=a['sha256'],hash_basis='existing M403 2026-10-23 upload SHA; this handoff compares size/mtime only',local='../SC/'+a['name'],state='EXISTS_BOTH_HISTORICAL_HASH'))
with (H/'迁移资产映射.tsv').open('w',encoding='utf-8-sig',newline='')as f:
 w=csv.DictWriter(f,fieldnames=list(rows[0]),delimiter='\t');w.writeheader();w.writerows(rows)
for n,v in r['deps'].items():
 content='# Observed '+r['start_utc']+'; ARM/Linux; metadata from inherited system + venv; NOT an install lock\n'
 content+='\n'.join(a['name']+'=='+a['version']for a in v.get('packages',[])if a.get('name'))+'\n'
 (H/('依赖_'+n.replace('.','')+'.txt')).write_text(content,encoding='utf8')
checks=[]
for a,b in [('orangepi/vendor/protocol.py','tools/m3/protocol.py'),('orangepi/vendor/M4_link_contract.md','docs/M4_link_contract.md')]:
 checks.append(dict(frozen=a,upstream=b,frozen_sha256=sha(ROOT/a),upstream_sha256=sha(ROOT/b),equal=sha(ROOT/a)==sha(ROOT/b)))
(H/'共享协议只读比较.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2),encoding='utf8')
training=ROOT/'orangepi/pc_traffic_20261024';wip=[]
for rel in ['标注规范.md','模型与部署路径.md','数据与划分方案.md','reports/gpu.csv','reports/nvcc.txt','data/archive_provenance.json','data/split_plan.json']:
 p=training/rel
 if p.exists():
  v=p.stat();wip.append(dict(path='orangepi/pc_traffic_20261024/'+rel,bytes=v.st_size,mtime_utc=datetime.datetime.fromtimestamp(v.st_mtime,datetime.timezone.utc).isoformat(),sha256=sha(p),state='WIP_EXTERNAL_WORK_NOT_FROZEN'))
(H/'PC准备工作只读索引.json').write_text(json.dumps(dict(at=datetime.datetime.now(datetime.timezone.utc).isoformat(),note='Metadata only: external task may keep changing. Not a training acceptance or stable package.',files=wip),ensure_ascii=False,indent=2),encoding='utf8')
index=[]
for p in sorted(H.glob('*')):
 if p.is_file()and p.name!='证据清单.sha256':index.append(sha(p)+'  '+p.name)
doc=H.parent/'香橙派完整开发交接.md';index.append(sha(doc)+'  ../'+doc.name)
(H/'证据清单.sha256').write_text('\n'.join(index)+'\n',encoding='utf8')
print('Mapped rows:',len(rows),'shared contract:',checks)
print('Remote-only/different model or wheel:',[a['remote']for a in rows if a['state']=='REMOTE_ONLY_OR_DIFFERENT'and Path(a['remote']).suffix in {'.rknn','.onnx','.pt','.whl'}])
