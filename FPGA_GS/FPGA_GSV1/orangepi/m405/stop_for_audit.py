import json,subprocess,base64
from pathlib import Path
c=json.loads(Path('oneclick/config.json').read_text());b=base64.b64encode(json.dumps(c).encode()).decode();r=subprocess.run(['ssh','orangepi@'+c['ssh_host'],f"cd {c['remote_dir']} && .venv/bin/python m405/demo_ops.py stop --config {b}"],capture_output=True,text=True,encoding='utf-8');assert json.loads(r.stdout)['ok'];print('M405 safely stopped for same-frame audit')
