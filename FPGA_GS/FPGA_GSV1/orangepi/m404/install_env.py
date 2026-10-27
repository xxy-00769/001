"""Reproduce the isolated environment with downloaded, sealed wheels only.
Never writes the system Python, original .venv, kernel or network settings.
"""
import hashlib,json,subprocess,zipfile
from pathlib import Path
root=Path(__file__).resolve().parents[1];base=root/'m404'
manifest=json.loads((base/'model_manifest.json').read_text())
for row in manifest['artifacts']:
 p=base/row['remote_path']
 if p.exists() and hashlib.sha256(p.read_bytes()).hexdigest()!=row['sha256']:raise RuntimeError('SHA256 mismatch: '+str(p))
subprocess.check_call(['python3','-m','venv','--without-pip','--system-site-packages',str(root/'.venv404')])
for name in ['rknn_lite.whl','ruamel_yaml.whl']:
 with zipfile.ZipFile(base/name) as z:z.extractall(root/'.venv404/lib/python3.10/site-packages')
print('M4-04 isolated runtime ready; ONNX Runtime is only required for model comparison.')
