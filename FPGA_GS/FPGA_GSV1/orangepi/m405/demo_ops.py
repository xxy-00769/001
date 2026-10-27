"""Own only this demo PID, and safely switch away from the existing project LIVE service."""
import sys,os,json,time,signal,subprocess,base64,argparse,fcntl
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'operator_v1'))
from ops_manager import proc,identity,owners,status,stop as stop_live,processes as live_processes

def expected(c):return ['.venv404/bin/python','m405/demo.py','--port',str(c['web_port']),'--preview-width',str(c.get('demo_preview_width',640))]
def matches(p,c):return bool(p and p['uid']==os.getuid() and p['cwd']==c['remote_dir'] and p['argv']==expected(c))
def saved(state):
 try:return json.loads((state/'demo_service.json').read_text())
 except (OSError,ValueError):return None
def stop(c,state):
 record=saved(state);p=proc(record['identity']['pid']) if record else None
 if not p:return dict(ok=True,message='智驾录像演示已经停止')
 if not identity(record['identity'],p) or not matches(p,c):return dict(ok=False,message='演示PID身份/参数已变化，拒绝停止',process=p)
 os.kill(p['pid'],signal.SIGINT);end=time.monotonic()+12
 while time.monotonic()<end:
  if not identity(p,proc(p['pid'])):return dict(ok=True,message='已正常停止智驾录像演示，原LIVE未自动启动')
  time.sleep(.1)
 return dict(ok=False,message='停止超时，未强制结束，查看演示日志',process=p)
def start(c,state):
 record=saved(state);p=proc(record['identity']['pid']) if record else None
 if p:
  if not identity(record['identity'],p) or not matches(p,c):return dict(ok=False,message='演示PID身份不符，未接管',process=p)
  s=status(c)
  if s.get('data',{}).get('instance')!=record.get('instance'):return dict(ok=False,message='已有演示进程但HTTP实例不符/未就绪')
  return dict(ok=True,message='已复用本项目智驾录像演示',process=p,status=s)
 # Refuse unrelated 8080 before stopping an owned LIVE service.
 ports=[r for r in owners(c) if r['local_port']==int(c['web_port'])]
 live=live_processes(c)
 if ports and (len(live)!=1 or any(x['pids']!=[live[0]['pid']] for x in ports)):
  return dict(ok=False,message='预览端口被其他程序占用；未结束任何进程',conflicts=ports)
 for x in json.loads((ROOT/'m403/media_manifest.json').read_text()):
  f=ROOT/'media'/x['name']
  if not f.exists() or f.stat().st_size!=x['bytes']:return dict(ok=False,message='素材缺失或大小不符：'+x['name'])
 (ROOT/'m403/evidence/media_verified.json').read_text()
 if live:
  result=stop_live(c,ROOT/'operator_v1/state')
  if not result['ok']:return result
 log=(state/'demo.console.log').open('ab')
 child=subprocess.Popen(expected(c),cwd=ROOT,stdin=subprocess.DEVNULL,stdout=log,stderr=log,env=dict(os.environ,OPENBLAS_NUM_THREADS="1",OMP_NUM_THREADS="1"),start_new_session=True,close_fds=True);log.close()
 p=None;s=None;end=time.monotonic()+45
 while time.monotonic()<end:
  if child.poll()is not None:return dict(ok=False,message='演示启动后退出，查看m405/state/demo.console.log')
  p=proc(child.pid);s=status(c)
  if matches(p,c):
   (state/'demo_service.json').write_text(json.dumps(dict(identity=p,instance=s.get('data',{}).get('instance'))))
  if s.get('data',{}).get('release')=='M4-05-r1' and (s.get('data',{}).get('detection') or {}).get('detection_fps',0)>0 and s.get('data',{}).get('road',{}).get('completed',0)>0:
   (state/'demo_service.json').write_text(json.dumps(dict(identity=p,instance=s['data']['instance'])))
   return dict(ok=True,message='已启动本地录像／模拟车辆；不绑定UDP，不需要FPGA',process=p,status=s)
  time.sleep(.2)
 return dict(ok=False,message='等待演示状态接口超时；PID已记录，使用停止智驾录像演示入口',process=p,status=s)
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('action',choices=['start','stop']);parser.add_argument('--config',required=True);a=parser.parse_args()
 try:
  c=json.loads(base64.b64decode(a.config));assert c['remote_dir']==str(ROOT)
  state=ROOT/'m405/state';state.mkdir(exist_ok=True)
  # Same remote lock as old oneclick, so LIVE start and demo start cannot race.
  with (ROOT/'operator_v1/state/operation.lock').open('a')as lock:
   fcntl.flock(lock,fcntl.LOCK_EX);result=globals()[a.action](c,state)
  print(json.dumps(result,ensure_ascii=False))
 except Exception as e:print(json.dumps(dict(ok=False,message=str(e)),ensure_ascii=False))
