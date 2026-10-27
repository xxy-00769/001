import subprocess,json
from pathlib import Path
HERE=Path(__file__).resolve().parent;c=json.loads((HERE.parent/'oneclick/config.json').read_text(encoding='utf8'));target=c['ssh_user']+'@'+c['ssh_host'];base=c['remote_dir']+'/m406/'
def copy(remote,local,recursive=False):
 subprocess.run(['scp','-P',str(c['ssh_port']),'-o','StrictHostKeyChecking=yes',*(['-r']if recursive else []),target+':'+remote,str(local)],check=True)
for name in ['exact_source','browser_videos']:copy(base+'evidence/'+name,HERE/'evidence',True)
copy(base+'evidence/remote_inventory.json',HERE/'evidence/remote_inventory.json')
if not (HERE/'backup/m405r2_preserved_source.tar.gz').exists():copy(base+'backup/m405r2_preserved_source.tar.gz',HERE/'backup/m405r2_preserved_source.tar.gz')
if not (HERE/'yolov8s640_fp16.rknn').exists():copy(base+'yolov8s640_fp16.rknn',HERE/'yolov8s640_fp16.rknn')
runtime=HERE/'evidence/runtime';runtime.mkdir(exist_ok=True);names=set()
for p in (HERE/'evidence/accepted').glob('*.json'):
 s=json.loads(p.read_text(encoding='utf8'))
 if s.get('snapshot'):names.add(s['snapshot'])
for p in (HERE/'evidence/playback').glob('*_snapshot.json'):
 s=json.loads(p.read_text(encoding='utf8'))
 if s.get('snapshot'):names.add(s['snapshot'])
for n in names:
 for suffix in ['.json','_raw.jpg','_overlay.jpg']:copy(base+'evidence/runtime/'+n+suffix,runtime/(n+suffix))
print('Evidence collected',len(names),'snapshots')
