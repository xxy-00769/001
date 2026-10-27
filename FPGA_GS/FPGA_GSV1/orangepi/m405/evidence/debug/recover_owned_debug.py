import sys,json,os,signal,time
from pathlib import Path
sys.path.insert(0,'operator_v1');from ops_manager import proc,identity
r=json.loads(Path('m405/state/demo_service.json').read_text());p=proc(r['identity']['pid'])
assert p and identity(r['identity'],p) and p['argv'][1]=='m405/demo.py'
os.kill(p['pid'],signal.SIGKILL);print('SIGKILL own after SIGINT/SIGTERM timeout verified M405',p['pid'])

