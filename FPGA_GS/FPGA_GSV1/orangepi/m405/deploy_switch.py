import json,base64,subprocess
from pathlib import Path
c=json.loads(Path('oneclick/config.json').read_text(encoding='utf-8-sig'));root=c['remote_dir'];b=base64.b64encode(json.dumps(c).encode()).decode()
for mod,action in [('m404','stop'),('m405','start')]:
 r=subprocess.run(['ssh','orangepi@'+c['ssh_host'],f'cd {root} && .venv/bin/python {mod}/demo_ops.py {action} --config {b}'],capture_output=True,text=True,encoding='utf-8');Path(f'm405/evidence/{mod}_{action}.json').write_text(r.stdout,encoding='utf-8');print(r.stdout[:1500]);print(r.stderr[:400])
 if not json.loads(r.stdout)['ok']:raise SystemExit(1)
