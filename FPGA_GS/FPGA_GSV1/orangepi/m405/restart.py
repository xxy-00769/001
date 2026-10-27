import json,subprocess,base64
from pathlib import Path
c=json.loads(Path('oneclick/config.json').read_text());b=base64.b64encode(json.dumps(c).encode()).decode()
for action in ['stop','start']:
 r=subprocess.run(['ssh','orangepi@'+c['ssh_host'],f"cd {c['remote_dir']} && .venv/bin/python m405/demo_ops.py {action} --config {b}"],capture_output=True,text=True,encoding='utf-8');Path('m405/evidence/npu_'+action+'.json').write_text(r.stdout,encoding='utf-8');s=json.loads(r.stdout);print(action,s['ok'],s.get('status',{}).get('data',{}).get('processed_fps'));assert s['ok']
