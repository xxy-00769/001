from pathlib import Path
import urllib.request,json,subprocess,hashlib
base=Path(__file__).parent;cfg=json.loads((base.parent/'oneclick/config.json').read_text(encoding='utf-8-sig'))
s=json.load(urllib.request.urlopen(f"http://127.0.0.1:{cfg['local_port']}/status.json?t=final",timeout=8));s.pop('control_token',None)
assert s['release']=='M4-05-r2' and s['mode']=='FILE_TEST' and not s['error'];assert s['road']['alive'] and not s['road']['error'];assert cfg['demo_ops']=='m405r2/demo_ops.py'
files=['demo.py','demo_ops.py','road.py','overlay.py','legacy_perception.py','driving.py','lane_semantics.py','index.html']
command="cd '"+cfg['remote_dir']+"' && sha256sum "+' '.join('m405r2/'+p for p in files)
r=subprocess.check_output(['ssh','-p',str(cfg['ssh_port']),'-o','StrictHostKeyChecking=yes',cfg['ssh_user']+'@'+cfg['ssh_host'],command],encoding='utf-8')
remote={line.split()[1].split('/')[-1]:line.split()[0] for line in r.splitlines()}
local={p:hashlib.sha256((base/p).read_bytes()).hexdigest()for p in files};assert local==remote
receipt=dict(current_status=s,config=cfg,code_sha256=local,local_remote_identical=True,r1_hash_check='all 16 original source/page hashes passed',rollback='m405r2 -> m405 PID22326 -> m405r2 PID22791; final label-only restart PID25633',udp='ss verified no UDP50000 listener; FPGA off',targeted_tests=json.loads((base/'evidence/targeted_tests.json').read_text(encoding='utf-8')),browser_controls='evidence/controls/checks.json',scope='offline road/lane r2 only; no historical whole-suite or FPGA tests')
(base/'evidence/final_receipt.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
print('final:',s['release'],s['video'],'processing',s['processed_fps'],'road/semantics',s['road']['update_fps'],'local/remote hashes identical')
