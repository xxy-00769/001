"""M4-01 foreground headless app. FILE_TEST never opens a business UDP socket."""
import argparse
import collections
import json
import signal
import secrets
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs
import cv2
import numpy as np
from vision import Vision
from playback import PlaybackClock

class App:
    def __init__(self,args):
        self.args=args; self.stop=threading.Event(); self.lock=threading.Lock()
        self.preview_ready=threading.Condition(self.lock)
        self.preview_sequence=0; self.preview_meta=None
        self.process_stamps=collections.deque(maxlen=240)
        self.stage_ms={}; self.playback={}
        self.latest=None; self.history=collections.OrderedDict(); self.jpeg=None
        self.received_frames=collections.OrderedDict()
        self.live_epoch=0;self.live_session=None;self.live_reset_monotonic=0.
        self.control_token=secrets.token_urlsafe(24)
        self.latest_pending=False; self.skipped_complete_frames=0
        self.raw_jpeg=None; self.latest_result={}; self.started=time.monotonic()
        self.count=0; self.times=[]; self.link=None; self.server=None
        self.out=Path(args.output); self.out.mkdir(parents=True,exist_ok=True)
        self.log_lock=threading.Lock()
        self.logfile=(self.out/'events.jsonl').open('a',encoding='utf-8')
        config=json.loads(Path(args.scene).read_text(encoding='utf-8-sig')) if args.scene else {}
        self.vision=Vision(config)

    def log(self,kind,**data):
        record=dict(type=kind,mode=self.args.mode,host_elapsed_ms=round((time.monotonic()-self.started)*1000,2))
        record.update(data)
        line=json.dumps(record,ensure_ascii=False)
        with self.log_lock:
            if self.logfile.tell()>10*1024*1024:
                self.logfile.close()
                old=self.out/'events.previous.jsonl'
                if old.exists(): old.unlink()
                (self.out/'events.jsonl').replace(old)
                self.logfile=(self.out/'events.jsonl').open('a',encoding='utf-8')
            print(line,flush=True); self.logfile.write(line+'\n'); self.logfile.flush()

    def publish(self,fid,image,received):
        with self.lock:
            if self.latest_pending:self.skipped_complete_frames+=1
            self.latest=(fid,image,received,self.live_epoch);self.latest_pending=True
            self.received_frames[fid]=received
            while len(self.received_frames)>128:
                self.received_frames.popitem(last=False)

    def reset_live(self,epoch,session,now,reason):
        with self.preview_ready:
            self.live_epoch=epoch;self.live_session=session;self.live_reset_monotonic=now
            self.latest=None;self.latest_pending=False
            self.history.clear();self.received_frames.clear();self.latest_result={}
            self.jpeg=self.raw_jpeg=self.preview_meta=None
            self.preview_sequence+=1;self.process_stamps.clear();self.stage_ms={}
            self.preview_ready.notify_all()

    def lookup(self,fid,now):
        with self.lock:
            item=self.history.get(fid)
            return item[1] if item and now-item[0]<2 else None

    def frame_state(self,fid,now):
        with self.lock:
            received=self.received_frames.get(fid)
            item=self.history.get(fid)
            return dict(received=received is not None,received_monotonic=received,
                        inference_complete=item is not None,
                        inference_stale=bool(item and now-item[0]>=2))

    def status(self):
        with self.lock:
            result=dict(self.latest_result)
        now=time.monotonic()
        age=now-result['received_monotonic'] if result else None
        with self.lock:
            stamps=[t for t in self.process_stamps if now-t<=5]
        rolling_fps=(len(stamps)-1)/max(.001,now-stamps[0]) if len(stamps)>1 else 0
        return dict(mode=self.args.mode,processed=self.count,
                    release='M4-02-r2-reconnect',live_epoch=self.live_epoch,
                    live_reset_monotonic_ms=self.live_reset_monotonic*1000,
                    control_token=self.control_token if self.args.mode=='LIVE_FRONT' else None,
                    requested_front_fps=self.args.front_fps if self.args.mode=='LIVE_FRONT' else None,
                    target_process_fps=self.args.front_fps if self.args.mode=='LIVE_FRONT' else self.args.sample_fps,
                    processing_policy='latest complete frame, no artificial throttle' if self.args.mode=='LIVE_FRONT' else 'native file timeline',
                    skipped_complete_frames=self.skipped_complete_frames,
                    host_monotonic_ms=now*1000,
                    processed_fps=round(rolling_fps,3),
                    processed_average_fps=round(self.count/max(.001,now-self.started),3),
                    target_preview_fps=getattr(self.args,'preview_fps',15),
                    preview_encoding=dict(width=getattr(self.args,'preview_width',1280),quality=getattr(self.args,'preview_quality',82)),
                    playback=dict(self.playback),stage_ms=dict(self.stage_ms),
                    preview_age_ms=round(age*1000,1) if age is not None else None,
                    effective_feedback='UNKNOWN_STALE' if self.args.mode!='FILE_TEST' and (age is None or age>=2) else 'SEE_EXACT_FRAME_DECISIONS',
                    latest=result,link=self.link.snapshot() if self.link else None)

    def preview(self):
        app=self
        preview_page=Path(__file__).with_name('preview.html').read_bytes()
        class Handler(BaseHTTPRequestHandler):
            protocol_version='HTTP/1.1'
            def setup(self):
                super().setup()
                # Reuse the tunnel's HTTP connection; avoid delayed small header writes.
                self.connection.setsockopt(socket.IPPROTO_TCP,socket.TCP_NODELAY,1)
                self.connection.settimeout(4)
            def log_message(self,*args): pass
            def end_headers(self):
                self.send_header('Cache-Control','no-store, no-cache, must-revalidate, max-age=0')
                self.send_header('Pragma','no-cache')
                self.send_header('Expires','0')
                super().end_headers()
            def do_GET(self):
                route=urlsplit(self.path).path
                if route=='/stream.mjpg':
                    self.stream(); return
                elif route=='/status.json':
                    body=json.dumps(app.status(),ensure_ascii=False).encode(); kind='application/json'
                elif route in ('/latest.jpg','/raw.jpg'):
                    after=parse_qs(urlsplit(self.path).query).get('after',[None])[0]
                    with app.preview_ready:
                        if route=='/latest.jpg' and after is not None and app.jpeg is not None:
                            app.preview_ready.wait_for(lambda: str(app.preview_sequence)!=after or app.stop.is_set(),timeout=.5)
                        body=app.jpeg if route=='/latest.jpg' else app.raw_jpeg
                        meta=app.preview_meta
                    if body is None: self.send_error(503,'Waiting for complete frame'); return
                    kind='image/jpeg'
                elif route=='/':
                    body=preview_page
                    kind='text/html; charset=utf-8'
                else: self.send_error(404); return
                self.send_response(200); self.send_header('Content-Type',kind)
                if kind=='image/jpeg' and meta is not None:
                    sequence,frame,received=meta
                    self.send_header('X-Frame-Sequence',str(sequence))
                    self.send_header('X-Frame-ID',str(frame))
                    self.send_header('X-Frame-Age-Ms',str(round((time.monotonic()-received)*1000,2)))
                self.send_header('Content-Length',str(len(body)))
                self.end_headers()
                try:
                    self.connection.settimeout(2)
                    self.wfile.write(body)
                except OSError: pass
            def do_POST(self):
                code=200
                try:
                    if urlsplit(self.path).path!='/feedback/control':
                        code=404; raise ValueError('接口不存在')
                    if app.args.mode!='LIVE_FRONT' or app.link is None:
                        code=409; raise ValueError('仅LIVE_FRONT允许通信自测，FILE_TEST不能绑定真实按键')
                    token=self.headers.get('X-M4-Control-Token','')
                    if not secrets.compare_digest(token,app.control_token):
                        code=403; raise ValueError('控制令牌失效，请刷新页面')
                    if self.headers.get('Content-Type','').split(';')[0]!='application/json':
                        code=415; raise ValueError('需要JSON请求')
                    length=int(self.headers.get('Content-Length','0'))
                    if not 0<length<=512: raise ValueError('请求长度无效')
                    data=json.loads(self.rfile.read(length))
                    controls=app.link.feedback.configure(data['mode'],data['selection'],time.monotonic())
                    result=dict(ok=True,controls=controls,message='已应用，仅对下一个真实FPGA驾驶EVENT生效；不会生成按键事件')
                except (ValueError,KeyError,TypeError) as error:
                    if code==200:code=400
                    self.close_connection=True
                    result=dict(ok=False,message=str(error))
                body=json.dumps(result,ensure_ascii=False).encode()
                self.send_response(code);self.send_header('Content-Type','application/json; charset=utf-8')
                self.send_header('Content-Length',str(len(body)));self.end_headers()
                try:self.wfile.write(body)
                except OSError:pass
            def stream(self):
                with app.lock: ready=app.jpeg is not None
                if not ready: self.send_error(503,'Waiting for complete frame'); return
                self.send_response(200)
                self.send_header('Content-Type','multipart/x-mixed-replace; boundary=frame')
                self.send_header('Connection','close'); self.end_headers()
                self.close_connection=True
                self.connection.settimeout(2)
                self.connection.setsockopt(socket.SOL_SOCKET,socket.SO_SNDBUF,32768)
                sent=None; due=time.monotonic()
                try:
                    while not app.stop.is_set():
                        if app.stop.wait(max(0,due-time.monotonic())): break
                        with app.preview_ready:
                            app.preview_ready.wait_for(lambda: app.preview_sequence!=sent or app.stop.is_set(),timeout=.5)
                            if app.stop.is_set(): break
                            if app.preview_sequence==sent: continue
                            body=app.jpeg; meta=app.preview_meta
                        if body is None or meta is None: return
                        sequence,frame,received=meta
                        headers=(f'--frame\r\nContent-Type: image/jpeg\r\nContent-Length: {len(body)}\r\n'
                                 f'X-Frame-Sequence: {sequence}\r\nX-Frame-ID: {frame}\r\n'
                                 f'X-Frame-Received-Ms: {received*1000:.3f}\r\n\r\n').encode()
                        # No frame queue: after each write, acquire only the latest publication.
                        self.wfile.write(headers+body+b'\r\n')
                        sent=sequence; due=max(due+1/getattr(app.args,'preview_fps',15),time.monotonic())
                except OSError: pass
        self.server=ThreadingHTTPServer(('127.0.0.1',self.args.web_port),Handler)
        self.server.daemon_threads=True
        threading.Thread(target=self.server.serve_forever,daemon=True).start()

    def process(self,fid,image,received,source_seconds=None,generation=None):
        with self.lock:
            if generation is not None and generation!=self.live_epoch:return
            frame_session=self.live_session
        process_started=time.perf_counter()
        wait_ms=(time.monotonic()-received)*1000
        raw565=image if isinstance(image,bytes) else None
        if isinstance(image,bytes):
            pixels=np.frombuffer(image,dtype='<u2').reshape(720,1280)
            image=np.stack(((pixels&31)*255//31,((pixels>>5)&63)*255//63,(pixels>>11)*255//31),axis=-1).astype(np.uint8)
        result,overlay=self.vision.analyze(image)
        result.update(frame_id=fid,received_monotonic=received,source_seconds=source_seconds,
                      complete_to_process_wait_ms=round(wait_ms,3),
                      frame_age_at_result_ms=round((time.monotonic()-received)*1000,2))
        for n,line in enumerate([f'{self.args.mode} frame={fid} CPU | scene configuration: SIMULATION',
            f"signal={result['signal']['state']} assoc={result['signal']['association']}",
            f"left={result['lanes']['left']['state']} right={result['lanes']['right']['state']} {result['inference_ms']:.1f}ms",
            ' '.join(f"K{k}:{['UNKNOWN','ALLOW','DENY'][v['code']]}" for k,v in result['decisions'].items())]):
            cv2.putText(overlay,line,(12,25+n*25),cv2.FONT_HERSHEY_SIMPLEX,.55,(255,200,0),2)
        encoding_started=time.perf_counter()
        preview_width=getattr(self.args,'preview_width',1280)
        preview=overlay if preview_width==overlay.shape[1] else cv2.resize(overlay,
            (preview_width,round(overlay.shape[0]*preview_width/overlay.shape[1])),interpolation=cv2.INTER_AREA)
        ok,encoded=cv2.imencode('.jpg',preview,[cv2.IMWRITE_JPEG_QUALITY,getattr(self.args,'preview_quality',82)])
        overlay_ms=(time.perf_counter()-encoding_started)*1000
        encoding_started=time.perf_counter()
        rawok,raw=cv2.imencode('.jpg',image,[cv2.IMWRITE_JPEG_QUALITY,85])
        raw_ms=(time.perf_counter()-encoding_started)*1000
        with self.preview_ready:
            if generation is not None and generation!=self.live_epoch:
                return  # An in-flight old inference cannot repopulate a new session's cache/JPEG.
            self.history[fid]=(received,result)
            while self.history and (len(self.history)>64 or time.monotonic()-next(iter(self.history.values()))[0]>2):
                self.history.popitem(last=False)
            self.latest_result=result
            if ok:
                self.jpeg=encoded.tobytes()
                self.preview_sequence+=1; self.preview_meta=(self.preview_sequence,fid,received)
                self.preview_ready.notify_all()
            if rawok: self.raw_jpeg=raw.tobytes()
        if self.link:self.link.feedback.inference_completed(fid,time.monotonic(),session=frame_session)
        self.count+=1; self.times.append(result['inference_ms'])
        if len(self.times)>10000: self.times=self.times[-5000:]
        if self.count==1 or self.count%self.args.snapshot_every==0:
            cv2.imwrite(str(self.out/f'overlay_{fid:08d}.jpg'),overlay)
            cv2.imwrite(str(self.out/f'raw_{fid:08d}.jpg'),image)
            if raw565 is not None:
                (self.out/f'raw_{fid:08d}.rgb565').write_bytes(raw565)
            # Keep a bounded number of sample pairs in continuous runs.
            for pattern in ('overlay_*.jpg','raw_*.jpg','raw_*.rgb565'):
                for old in sorted(self.out.glob(pattern))[:-12]: old.unlink()
        self.stage_ms=dict(inference=result['inference_ms'],overlay_jpeg=round(overlay_ms,2),
                           overlay_jpeg_bytes=len(encoded) if ok else 0,
                           raw_jpeg=round(raw_ms,2),process_total=round((time.perf_counter()-process_started)*1000,2))
        self.log('observation',**result,stage_ms=self.stage_ms)
        with self.lock: self.process_stamps.append(time.monotonic())

    def run(self):
        self.preview()
        self.log('startup',execution='CPU',opencv=cv2.__version__,numpy=np.__version__,
                 web=f'http://127.0.0.1:{self.args.web_port}',release='M4-02-r2-reconnect',
                 hardware_validation='前摄15fps已实测；真实按键及双口并行需本轮验收')
        try:
            if self.args.mode=='FILE_TEST': self.file()
            else: self.live()
        finally:
            active_seconds=time.monotonic()-self.started
            self.stop.set()
            with self.preview_ready: self.preview_ready.notify_all()
            if self.link: self.link.stop.set(); self.worker.join(timeout=2)
            self.server.shutdown(); self.server.server_close()
            summary=self.status()
            summary.update(inference_mean_ms=round(float(np.mean(self.times)),3) if self.times else None,
                           inference_p95_ms=round(float(np.percentile(self.times,95)),3) if self.times else None,
                           active_seconds=round(active_seconds,3),
                           pipeline_fps=round(self.count/max(.001,active_seconds),3))
            (self.out/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
            self.log('shutdown',**summary); self.logfile.close()

    def file(self):
        cap=cv2.VideoCapture(self.args.video)
        if not cap.isOpened(): raise RuntimeError('Cannot open video: '+self.args.video)
        fps=cap.get(cv2.CAP_PROP_FPS)
        frame_count=int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        clock=PlaybackClock(fps,frame_count,self.args.sample_fps,time.monotonic())
        due=clock.start; cycle=0; cursor=-1; skipped=0; benchmark_tick=0
        self.playback=dict(source_fps=fps,target_process_fps=clock.target_fps,media_duration_seconds=clock.duration,
                           loop_index=0,skipped_source_frames=0,source_frame_index=None,media_lag_ms=0)
        try:
            while not self.stop.is_set():
                if self.args.duration and time.monotonic()-self.started>=self.args.duration: break
                if self.args.max_frames and self.count>=self.args.max_frames: break
                if not self.args.benchmark:
                    if self.stop.wait(max(0,due-time.monotonic())): break
                    now=time.monotonic()
                else:
                    now=clock.start+benchmark_tick/clock.target_fps; benchmark_tick+=1
                next_cycle,target,due=clock.locate(now)
                if next_cycle and not self.args.loop: break
                if next_cycle!=cycle:
                    if not cap.set(cv2.CAP_PROP_POS_FRAMES,0): raise RuntimeError('Cannot rewind video')
                    cycle=next_cycle; cursor=-1
                    self.log('file_loop',loop_index=cycle,host_playback_seconds=round(now-clock.start,3),
                             media_duration_seconds=clock.duration)
                if target<=cursor: continue
                skipped+=max(0,target-cursor-1)
                while cursor<target:
                    if not cap.grab(): raise RuntimeError('Unexpected EOF before declared file duration')
                    cursor+=1
                ok,image=cap.retrieve()
                if not ok: raise RuntimeError('Cannot decode selected native frame')
                received=time.monotonic(); source_seconds=cursor/fps
                self.playback.update(loop_index=cycle,source_frame_index=cursor,source_seconds=source_seconds,
                    skipped_source_frames=skipped,
                    media_lag_ms=round((received-clock.start-cycle*clock.duration-source_seconds)*1000,2))
                self.process(cycle*frame_count+cursor+1,image,received,source_seconds)
        finally: cap.release()

    def live(self):
        from link import Link
        self.link=Link((self.args.bind,self.args.port),(self.args.peer,self.args.peer_port),self.publish,self.lookup,self.log,
                       front_fps=self.args.front_fps,frame_state=self.frame_state)
        self.link.reset_live=self.reset_live
        self.live_session=self.link.session
        self.worker=threading.Thread(target=self.link.run,daemon=True); self.worker.start()
        consumed=None
        while not self.stop.wait(.005):
            if self.args.duration and time.monotonic()-self.started>=self.args.duration: break
            with self.lock:
                item=self.latest if self.latest_pending else None
                if item:self.latest_pending=False
            if item and (item[3],item[0])!=consumed:
                consumed=(item[3],item[0]); self.process(*item[:3],generation=item[3])

def parse():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--mode',choices=['FILE_TEST','LIVE_FRONT','SIMULATION'],required=True)
    p.add_argument('--video'); p.add_argument('--scene')
    p.add_argument('--output',default='runs/current'); p.add_argument('--web-port',type=int,default=8080)
    p.add_argument('--duration',type=float,default=0); p.add_argument('--max-frames',type=int,default=0)
    p.add_argument('--sample-fps',type=float,default=15); p.add_argument('--benchmark',action='store_true')
    p.add_argument('--front-fps',type=int,default=15,help='LIVE_FRONT HELLO upload request, integer 0..30; 0 stops upload')
    p.add_argument('--preview-fps',type=float,default=15,help='MJPEG publication target; one streaming connection per browser')
    p.add_argument('--preview-width',type=int,default=1280,help='Only Web JPEG width; inference/raw/snapshots retain original resolution')
    p.add_argument('--preview-quality',type=int,default=82,help='Only Web overlay JPEG quality (30..95)')
    p.add_argument('--loop',action='store_true',help='Replay FILE_TEST until Ctrl+C or --duration')
    p.add_argument('--snapshot-every',type=int,default=25)
    p.add_argument('--bind'); p.add_argument('--peer'); p.add_argument('--port',type=int,default=50000)
    p.add_argument('--peer-port',type=int,default=50000)
    p.add_argument('--link-config',help='JSON endpoint values; never changes OS networking')
    args=p.parse_args()
    if not 0<=args.front_fps<=30:p.error('front-fps must be an integer in 0..30')
    if args.link_config:
        endpoints=json.loads(Path(args.link_config).read_text(encoding='utf-8-sig'))
        args.bind=args.bind or endpoints['bind']
        args.peer=args.peer or endpoints['peer']
        args.port=endpoints.get('port',args.port)
        args.peer_port=endpoints.get('peer_port',args.peer_port)
    if args.mode=='FILE_TEST' and not args.video: p.error('FILE_TEST requires --video')
    if args.mode!='FILE_TEST' and (not args.bind or not args.peer): p.error('Network modes require explicit --bind and --peer from agreed contract')
    if args.mode=='SIMULATION' and (args.bind!='127.0.0.1' or args.peer!='127.0.0.1'):
        p.error('SIMULATION transport is restricted to loopback')
    if args.sample_fps<=0 or not 0<args.preview_fps<=30 or args.snapshot_every<1:
        p.error('Positive sample-fps/snapshot-every and preview-fps in (0,30] required')
    if not 320<=args.preview_width<=1280 or not 30<=args.preview_quality<=95:
        p.error('preview-width in [320,1280] and preview-quality in [30,95] required')
    return args

if __name__=='__main__':
    app=App(parse())
    signal.signal(signal.SIGINT,lambda *_:app.stop.set())
    signal.signal(signal.SIGTERM,lambda *_:app.stop.set())
    app.run()
