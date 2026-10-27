import subprocess,json
from pathlib import Path
r=Path(__file__).resolve().parents[1];base=r.parent
ps=[Path('C:/Users/YuHuang/AppData/Local/Programs/Python/Python39/python.exe'),Path('C:/Users/YuHuang/AppData/Local/Programs/Python/Python38/python.exe'),base/'.venv/Scripts/python.exe',base/'.venv312/Scripts/python.exe']
code="import sys,importlib.metadata as m,json; print(json.dumps({'executable':sys.executable,'version':sys.version,'packages':{p: next((d.version for d in m.distributions() if d.metadata['Name'].lower().replace('_','-')==p),None) for p in ['torch','torchvision','ultralytics','onnx','onnxruntime','opencv-python','opencv-python-headless','numpy','rknn-toolkit2']}}))"
out=[]
for p in ps:
 if p.exists():
  run=subprocess.run([str(p),'-c',code],capture_output=True,text=True,timeout=30);out.append(json.loads(run.stdout) if run.returncode==0 else {'executable':str(p),'error':run.stderr})
(r/'reports/existing_environments.json').write_text(json.dumps(out,indent=2),encoding='utf-8');print('environment inventory saved')
