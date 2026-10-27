import json,hashlib
from pathlib import Path
r=json.loads(Path('m405/deployment_manifest.json').read_text());rows=[]
for name,expected in r['files'].items():
 actual=hashlib.sha256(Path(name).read_bytes()).hexdigest();rows.append(dict(file=name,match=actual==expected))
assert all(x['match'] for x in rows),rows
Path('m405/evidence/deployed_hash_check.json').write_text(json.dumps(rows,indent=2));print('remote release files verified',len(rows))
