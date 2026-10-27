import json
from pathlib import Path
rows=[]
for l in (Path(__file__).resolve().parent/'evidence/runtime/actions.jsonl').open():
 x=json.loads(l)
 if x['type']=='control':rows.append(x)
for x in rows[-8:]:print(x['host_monotonic'],x['position'],x['command'],x['driving'])
