from pathlib import Path
import json,hashlib
p=Path('orangepi/m404');f=p/'model_manifest.json';m=json.loads(f.read_text(encoding='utf-8'));m['deployment']='RK3588S RKNN/NPU; requested mask NPU_CORE_0_1_2, not a measured per-core utilization claim';f.write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
manifest=[]
for name in ['demo.py','detector.py','overlay.py','index.html','demo_ops.py']:
 f=p/name;manifest.append(dict(path='m404/'+name,sha256=hashlib.sha256(f.read_bytes()).hexdigest()))
for name in ['config.json','demo_launcher.ps1','set_demo_version.ps1','启动智驾录像演示.cmd','停止智驾录像演示.cmd','回退M4-03录像演示.cmd','切回M4-04人车检测.cmd']:
 f=p.parent/'oneclick'/name;manifest.append(dict(path='oneclick/'+name,sha256=hashlib.sha256(f.read_bytes()).hexdigest()))
(p/'deployment_manifest.json').write_text(json.dumps(dict(release='M4-04-r1',remote_dir='/home/orangepi/fpga_gs_m401_v0_1_2_20261021',files=manifest),ensure_ascii=False,indent=2),encoding='utf-8')
