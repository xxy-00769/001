"""Offline-only road demonstration. Never imports Link or binds a UDP socket."""
import argparse,bisect,collections,json,secrets,signal,socket,subprocess,threading,time
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from urllib.parse import urlsplit,parse_qs
import cv2,numpy as np
from perception import Perception
from driving import Driving
from overlay import draw

ROOT=Path(__file__).resolve().parents[1];VERSION='M4-03-demo-r1'
class Demo:
 def __init__(self,args):
  self.args=args;self.stop=threading.Event();self.lock=threading.RLock();self.ready=threading.Condition(self.lock)
  self.token=secrets.token_urlsafe(24);self.instance=secrets.token_hex(12)
  self.media=json.loads((ROOT/'m403/evidence/media_verified.json').read_text());self.scenes=json.loads((ROOT/'m403/scenes.json').read_text())
  self.files={x['name']:x for x in self.media};self.video='SC_YJ.mp4';self.epoch=0;self.command_revision=0
  self.position=0.;self.playing=True;self.loop=True;self.width=args.preview_width;self.seek=70.;self.reopen=True
  self.driver=Driving();self.perception=Perception(self.scenes[self.video]);self.sequence=0
  self.jpeg=None;self.raw=None;self.raw_image=None;self.obs=None;self.frame=None;self.stage={};self.last_render=0.;self.evidence_at=0.;self.published_drive=None
  self.processed=0;self.skipped=0;self.loops=0;self.stamps=collections.deque(maxlen=240);self.stage_history=collections.deque(maxlen=450)
  self.pts={};self.timelines={};self.last_error=None;self.last_paused_drive=None
  self.out=ROOT/'m403/evidence/runtime';self.out.mkdir(exist_ok=True)
  self.log=(self.out/'actions.jsonl').open('a',encoding='utf-8');self.last_log=0
 def record(self,kind,**kw):
  self.log.write(json.dumps(dict(type=kind,host_monotonic=time.monotonic(),video=self.video,epoch=self.epoch,position=self.position,**kw),ensure_ascii=False)+'\n');self.log.flush()
 def reset(self):
  mode=self.driver.mode;lane=self.driver.lane;self.driver.reset();self.driver.mode=mode;self.driver.lane=lane
  self.epoch+=1;self.perception=Perception(self.scenes[self.video]);self.obs=None;self.jpeg=None;self.raw=None;self.raw_image=None;self.frame=None;self.evidence_at=0.;self.stamps.clear();self.ready.notify_all()
 def status(self):
  with self.lock:
   now=time.monotonic();times=[s for s in self.stamps if now-s<=5]
   averages={k:round(float(np.mean([x[k] for x in self.stage_history if k in x])),3) for k in self.stage}
   return dict(mode='FILE_TEST',vehicle='SIMULATION',release=VERSION,instance=self.instance,control_token=self.token,host_monotonic_ms=now*1000,video=self.video,
    files=[dict(name=x['name'],duration=x['duration_seconds'],fps=x['source_fps'],label=self.scenes[x['name']]['label']) for x in self.media],
    source_fps=self.files[self.video]['source_fps'],duration=self.files[self.video]['duration_seconds'],position=self.position,playing=self.playing,loop=self.loop,epoch=self.epoch,
    processed=self.processed,processed_fps=round((len(times)-1)/max(.001,now-times[0]),3) if len(times)>1 else 0,skipped_source_frames=self.skipped,loop_count=self.loops,
    target_fps=15,preview_width=self.width,frame_id=self.frame,sequence=self.sequence,age_ms=round((now-self.evidence_at)*1000,1) if self.evidence_at else None,
    driving=self.driver.snapshot(),perception=self.obs,stage_ms=self.stage,stage_mean_ms=averages,error=self.last_error,
    note='模拟车辆与原录像车辆独立；录像运动不因模拟停车而冻结。无UDP、无FPGA事件；图龄从本机解码完成起算。')
 def control(self,data):
  with self.ready:
   if data.get('snapshot'):
    if self.raw_image is None or self.jpeg is None:return dict(ok=False,error='等待首帧，尚无可保存图像')
    expected=data.get('snapshot_expected',{});d=self.published_drive or {};o=self.obs
    actual=dict(motion=d.get('motion'),signal=o['signal']['state'],left=o['lanes']['left']['state'],right=o['lanes']['right']['state'],alarm=bool(d.get('alarm')))
    if any(actual.get(k)!=v for k,v in expected.items()):return dict(ok=False,error='当前帧尚未满足截图条件',actual=actual)
    stamp=time.strftime('%Y%m%d_%H%M%S');base=f'{self.video[:-4]}_{self.position:.3f}_{stamp}_{self.sequence}'
    cv2.imwrite(str(self.out/(base+'_raw.jpg')),self.raw_image,[cv2.IMWRITE_JPEG_QUALITY,95])
    (self.out/(base+'_overlay.jpg')).write_bytes(self.jpeg)
    saved=self.status();saved.pop('control_token',None);saved['driving']=d
    (self.out/(base+'.json')).write_text(json.dumps(saved,ensure_ascii=False,indent=2))
    return dict(ok=True,snapshot=base,directory=str(self.out),status=saved)
   if 'video'in data:
    if data['video']not in self.files:raise ValueError('未知视频')
    self.video=data['video'];self.seek=0.;self.reopen=True;self.reset()
   if 'seek'in data:
    self.seek=float(data['seek'])
    if not np.isfinite(self.seek):raise ValueError('跳转时间无效')
    self.seek=max(0,min(self.files[self.video]['duration_seconds']-.1,self.seek));self.reopen=True;self.reset()
   if data.get('restart'):self.seek=0.;self.reopen=True;self.reset()
   if 'playing'in data:self.playing=bool(data['playing'])
   if 'loop'in data:self.loop=bool(data['loop'])
   if 'width'in data:
    if int(data['width'])not in (640,1280):raise ValueError('预览仅640/1280')
    self.width=int(data['width'])
   if 'signal_roi'in data:
    raise ValueError('本版仅使用已核对的灯体外壳和方向标定；不接受只有颜色区域的放行标定')
   self.driver.command(data,time.monotonic());self.command_revision+=1
   self.driver.update(self.obs,time.monotonic()-self.evidence_at if self.evidence_at else 999,time.monotonic())
   self.record('control',command=data,driving=self.driver.snapshot());self.ready.notify_all()
  return dict(ok=True)
 def timestamps(self,video):
  if video not in self.pts:
   p=ROOT/'media'/video;cache=ROOT/'m403'/f'{video}.pts.json'
   if cache.exists():pts=json.loads(cache.read_text())
   else:
    r=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','packet=pts_time','-of','json',str(p)]))
    pts=sorted(float(x['pts_time']) for x in r['packets'] if 'pts_time'in x)
    if len(pts)!=self.files[video]['frame_count']:raise ValueError('视频PTS数量与实际帧数不一致，拒绝用平均fps猜测')
    first=pts[0];pts=[x-first for x in pts];cache.write_text(json.dumps(pts))
   if not pts or any(b<a for a,b in zip(pts,pts[1:])):raise ValueError('视频时间戳无效')
   self.pts[video]=pts
  return self.pts[video]
 def render(self,raw,obs,drive,sec,video,width):
  start=time.perf_counter();annotated=draw(raw,obs,drive,width,video,sec);overlay_ms=(time.perf_counter()-start)*1000
  start=time.perf_counter();ok,jpeg=cv2.imencode('.jpg',annotated,[cv2.IMWRITE_JPEG_QUALITY,70]);jpeg_ms=(time.perf_counter()-start)*1000
  if not ok:raise RuntimeError('JPEG编码失败')
  return jpeg.tobytes(),dict(overlay=round(overlay_ms,3),jpeg=round(jpeg_ms,3))
 def run(self):
  self.http();cap=None;clock=0;cursor=-1;was_playing=True;due=time.monotonic();last_revision=-1
  try:
   while not self.stop.is_set():
    with self.lock:reopen=self.reopen;video=self.video;epoch=self.epoch;seek=self.seek;playing=self.playing;revision=self.command_revision;perception=self.perception
    if reopen:
     if cap:cap.release()
     pts=self.timestamps(video);cap=cv2.VideoCapture(str(ROOT/'media'/video))
     if not cap.isOpened():raise RuntimeError('无法打开视频')
     target=max(0,bisect.bisect_right(pts,seek)-1)
     # OpenCV's FFmpeg backend approximates POS_FRAMES seeks using average fps.
     # That is not a valid frame index for the 25/50ms VFR original. Reopen and
     # advance the native decode order before starting its playback clock.
     variable=self.files[video]['pts_step_max']>self.files[video]['pts_step_min']*1.2
     if variable:
      for _ in range(target):
       if self.stop.is_set():break
       if not cap.grab():raise RuntimeError('变帧率录像定位失败')
     elif not cap.set(cv2.CAP_PROP_POS_FRAMES,target):raise RuntimeError('录像定位失败')
     cursor=target-1
     clock=time.monotonic()-seek;due=time.monotonic();was_playing=playing
     with self.lock:
      if epoch!=self.epoch:continue
      self.reopen=False;self.position=seek
    if not playing and self.raw_image is not None:
     with self.lock:
      drive=self.driver.update(self.obs,time.monotonic()-self.evidence_at,time.monotonic());raw=self.raw_image;obs=self.obs;sec=self.position;width=self.width
     signature=(drive['motion'],drive['reason'],drive['alarm'],drive['intent'])
     if revision!=last_revision or signature!=self.last_paused_drive:
      body,_=self.render(raw,obs,drive,sec,video,width)
      with self.ready:
       if epoch==self.epoch:self.jpeg=body;self.published_drive=drive;self.sequence+=1;self.ready.notify_all()
      last_revision=revision;self.last_paused_drive=signature
     was_playing=False;self.stop.wait(.03);continue
    if not was_playing:clock=time.monotonic()-self.position;due=time.monotonic();was_playing=True
    if self.stop.wait(max(0,due-time.monotonic())):break
    cycle_position=max(0,time.monotonic()-clock)
    if cycle_position>=self.files[video]['duration_seconds']:
     with self.ready:
      if self.loop:self.loops+=1;self.seek=0.;self.reopen=True;self.reset();self.record('loop_reset')
      else:self.playing=False;self.driver.command(dict(intent='stop'),time.monotonic())
     continue
    target=max(0,bisect.bisect_right(pts,cycle_position)-1)
    if target<=cursor:
     due=time.monotonic()+.003;continue
    start=time.perf_counter();skipped=max(0,target-cursor-1)
    while cursor<target:
     if not cap.grab():raise RuntimeError('视频提前结束')
     cursor+=1
    ok,image=cap.retrieve();decode_ms=(time.perf_counter()-start)*1000
    if not ok:raise RuntimeError('无法解码原始帧')
    # Keep this epoch's classifier object: a concurrent seek must not let an old
    # decoded image seed the newly reset classifier's temporal votes.
    decoded=time.monotonic();sec=pts[cursor];obs=perception.analyze(image)
    rules_start=time.perf_counter()
    with self.lock:
     if epoch!=self.epoch:continue
     drive=self.driver.update(obs,time.monotonic()-decoded,time.monotonic());width=self.width
    rule_ms=(time.perf_counter()-rules_start)*1000
    body,stage=self.render(image,obs,drive,sec,video,width)
    stage.update(decode=round(decode_ms,3),**obs['stage_ms'],rules=round(rule_ms,3),total=round((time.perf_counter()-start)*1000,3),timeline_lag_ms=round((time.monotonic()-clock-sec)*1000,2))
    with self.ready:
     if epoch!=self.epoch:continue
     self.jpeg=body;self.published_drive=drive;self.raw=None;self.raw_image=image;self.obs=obs;self.position=sec;self.frame=cursor;self.evidence_at=decoded
     self.sequence+=1;self.processed+=1;self.skipped+=skipped;self.stage=stage;self.stage_history.append(stage);self.stamps.append(time.monotonic());self.ready.notify_all()
     if time.monotonic()-self.last_log>=1:
      self.record('observation',frame=cursor,driving=drive,perception=obs,stage_ms=stage);self.last_log=time.monotonic()
    last_revision=revision;due=max(due+1/15,time.monotonic())
  except Exception as error:
   self.last_error=repr(error);self.record('error',error=repr(error));raise
  finally:
   if cap:cap.release()
   self.stop.set();self.server.shutdown();self.server.server_close();self.log.close()
 def http(self):
  app=self
  class Handler(BaseHTTPRequestHandler):
   protocol_version='HTTP/1.1'
   def log_message(self,*args):pass
   def setup(self):
    super().setup();self.connection.settimeout(3);self.connection.setsockopt(socket.IPPROTO_TCP,socket.TCP_NODELAY,1)
   def reply(self,body,kind='application/json; charset=utf-8',code=200,extra=None):
    self.send_response(code);self.send_header('Content-Type',kind);self.send_header('Cache-Control','no-store, no-cache, must-revalidate');self.send_header('Pragma','no-cache');self.send_header('Expires','0');self.send_header('Content-Length',str(len(body)))
    for name,value in (extra or {}).items():self.send_header(name,str(value))
    self.end_headers()
    try:self.wfile.write(body)
    except OSError:pass
   def do_GET(self):
    route=urlsplit(self.path).path
    if route=='/':self.reply((ROOT/'m403/index.html').read_bytes(),'text/html; charset=utf-8')
    elif route=='/status.json':self.reply(json.dumps(app.status(),ensure_ascii=False).encode())
    elif route=='/frame.jpg':
     after=parse_qs(urlsplit(self.path).query).get('after',[''])[0]
     with app.ready:
      app.ready.wait_for(lambda:app.stop.is_set() or (app.jpeg and str(app.sequence)!=after),timeout=.8)
      body=app.jpeg;seq=app.sequence;identity=f'{app.epoch}:{app.frame}';received=app.evidence_at
     if not body or str(seq)==after:self.reply(b'','text/plain',204)
     else:self.reply(body,'image/jpeg',extra={'X-Frame-Sequence':seq,'X-Frame-ID':identity,'X-Frame-Received-Ms':f'{received*1000:.3f}'})
    elif route=='/stream.mjpg':self.stream()
    elif route in ('/latest.jpg','/raw.jpg'):
     with app.lock:raw=app.raw_image;body=app.jpeg
     if route=='/raw.jpg' and raw is not None:body=cv2.imencode('.jpg',raw,[cv2.IMWRITE_JPEG_QUALITY,90])[1].tobytes()
     self.reply(body or b'Waiting for first frame','image/jpeg' if body else 'text/plain',200 if body else 503)
    else:self.reply(b'not found','text/plain',404)
   def do_POST(self):
    try:
     if urlsplit(self.path).path!='/demo/control':self.reply(b'not found','text/plain',404);return
     if not secrets.compare_digest(self.headers.get('X-M4-Control-Token',''),app.token):raise ValueError('令牌失效，刷新页面')
     length=int(self.headers.get('Content-Length',0))
     if not 0<length<=2048:raise ValueError('请求过长')
     reply=app.control(json.loads(self.rfile.read(length)));self.reply(json.dumps(reply).encode())
    except (ValueError,KeyError,TypeError) as e:self.reply(json.dumps(dict(ok=False,error=str(e)),ensure_ascii=False).encode(),code=400)
   def stream(self):
    self.send_response(200);self.send_header('Cache-Control','no-store');self.send_header('Content-Type','multipart/x-mixed-replace; boundary=frame');self.send_header('Connection','close');self.end_headers();self.close_connection=True
    self.connection.setsockopt(socket.SOL_SOCKET,socket.SO_SNDBUF,32768);sent=-1
    try:
     while not app.stop.is_set():
      with app.ready:
       app.ready.wait_for(lambda:app.stop.is_set() or app.sequence!=sent,timeout=.5)
       if not app.jpeg or app.sequence==sent:continue
       body=app.jpeg;seq=app.sequence;frame=app.frame;epoch=app.epoch;received=app.evidence_at
      headers=f'--frame\r\nContent-Type: image/jpeg\r\nContent-Length: {len(body)}\r\nX-Frame-Sequence: {seq}\r\nX-Frame-ID: {epoch}:{frame}\r\nX-Frame-Received-Ms: {received*1000:.3f}\r\n\r\n'.encode()
      self.wfile.write(headers+body+b'\r\n');sent=seq
    except OSError:pass
  self.server=ThreadingHTTPServer(('127.0.0.1',self.args.port),Handler);self.server.daemon_threads=True
  threading.Thread(target=self.server.serve_forever,daemon=True).start()

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=8080);p.add_argument('--preview-width',type=int,default=640,choices=[640,1280]);app=Demo(p.parse_args())
 signal.signal(signal.SIGINT,lambda *_:app.stop.set());signal.signal(signal.SIGTERM,lambda *_:app.stop.set());app.run()
