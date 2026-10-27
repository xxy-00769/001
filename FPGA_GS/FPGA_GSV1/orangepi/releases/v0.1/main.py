"""M4-01 foreground headless app. FILE_TEST never opens a business UDP socket."""
import argparse
import collections
import json
import signal
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import cv2
import numpy as np
from vision import Vision

class App:
    def __init__(self,args):
        self.args=args; self.stop=threading.Event(); self.lock=threading.Lock()
        self.latest=None; self.history=collections.OrderedDict(); self.jpeg=None
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
        with self.lock: self.latest=(fid,image,received)

    def lookup(self,fid,now):
        with self.lock:
            item=self.history.get(fid)
            return item[1] if item and now-item[0]<2 else None

    def status(self):
        with self.lock:
            result=dict(self.latest_result)
        now=time.monotonic()
        age=now-result['received_monotonic'] if result else None
        return dict(mode=self.args.mode,processed=self.count,
                    processed_fps=round(self.count/max(.001,now-self.started),3),
                    preview_age_ms=round(age*1000,1) if age is not None else None,
                    effective_feedback='UNKNOWN_STALE' if self.args.mode!='FILE_TEST' and (age is None or age>=2) else 'SEE_EXACT_FRAME_DECISIONS',
                    latest=result,link=self.link.snapshot() if self.link else None)

    def preview(self):
        app=self
        class Handler(BaseHTTPRequestHandler):
            def log_message(self,*args): pass
            def do_GET(self):
                if self.path=='/status.json':
                    body=json.dumps(app.status(),ensure_ascii=False).encode(); kind='application/json'
                elif self.path in ('/latest.jpg','/raw.jpg'):
                    with app.lock: body=app.jpeg if self.path=='/latest.jpg' else app.raw_jpeg
                    if body is None: self.send_error(503,'Waiting for complete frame'); return
                    kind='image/jpeg'
                elif self.path=='/':
                    body=b'''<!doctype html><meta charset="utf-8"><title>M4-01</title>
<style>body{background:#15202b;color:white;font:16px monospace}img{width:96vw;max-width:1280px}pre{white-space:pre-wrap}</style>
<h2>M4-01 CPU preview / driving intent simulation</h2><img id="image"><pre id="status"></pre>
<script>setInterval(async()=>{document.getElementById('image').src='/latest.jpg?t='+Date.now();document.getElementById('status').textContent=JSON.stringify(await(await fetch('/status.json')).json(),null,2)},500)</script>'''
                    kind='text/html; charset=utf-8'
                else: self.send_error(404); return
                self.send_response(200); self.send_header('Content-Type',kind)
                self.send_header('Cache-Control','no-store'); self.send_header('Content-Length',str(len(body)))
                self.end_headers()
                try: self.wfile.write(body)
                except (BrokenPipeError,ConnectionResetError): pass
        self.server=ThreadingHTTPServer(('127.0.0.1',self.args.web_port),Handler)
        self.server.daemon_threads=True
        threading.Thread(target=self.server.serve_forever,daemon=True).start()

    def process(self,fid,image,received,source_seconds=None):
        raw565=image if isinstance(image,bytes) else None
        if isinstance(image,bytes):
            pixels=np.frombuffer(image,dtype='<u2').reshape(720,1280)
            image=np.stack(((pixels&31)*255//31,((pixels>>5)&63)*255//63,(pixels>>11)*255//31),axis=-1).astype(np.uint8)
        result,overlay=self.vision.analyze(image)
        result.update(frame_id=fid,received_monotonic=received,source_seconds=source_seconds,
                      frame_age_at_result_ms=round((time.monotonic()-received)*1000,2))
        for n,line in enumerate([f'{self.args.mode} frame={fid} CPU | scene configuration: SIMULATION',
            f"signal={result['signal']['state']} assoc={result['signal']['association']}",
            f"left={result['lanes']['left']['state']} right={result['lanes']['right']['state']} {result['inference_ms']:.1f}ms",
            ' '.join(f"K{k}:{['UNKNOWN','ALLOW','DENY'][v['code']]}" for k,v in result['decisions'].items())]):
            cv2.putText(overlay,line,(12,25+n*25),cv2.FONT_HERSHEY_SIMPLEX,.55,(255,200,0),2)
        ok,encoded=cv2.imencode('.jpg',overlay,[cv2.IMWRITE_JPEG_QUALITY,82])
        rawok,raw=cv2.imencode('.jpg',image,[cv2.IMWRITE_JPEG_QUALITY,85])
        with self.lock:
            self.history[fid]=(received,result)
            while self.history and (len(self.history)>16 or time.monotonic()-next(iter(self.history.values()))[0]>2):
                self.history.popitem(last=False)
            self.latest_result=result
            if ok: self.jpeg=encoded.tobytes()
            if rawok: self.raw_jpeg=raw.tobytes()
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
        self.log('observation',**result)

    def run(self):
        self.preview()
        self.log('startup',execution='CPU',opencv=cv2.__version__,numpy=np.__version__,
                 web=f'http://127.0.0.1:{self.args.web_port}',hardware_validation='网口2尚未实物联调')
        try:
            if self.args.mode=='FILE_TEST': self.file()
            else: self.live()
        finally:
            active_seconds=time.monotonic()-self.started
            self.stop.set()
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
        fps=cap.get(cv2.CAP_PROP_FPS) or 25
        step=max(1,round(fps/self.args.sample_fps)); fid=0; source_frame=0; due=time.monotonic()
        try:
            while not self.stop.is_set():
                if self.args.duration and time.monotonic()-self.started>=self.args.duration: break
                if self.args.max_frames and self.count>=self.args.max_frames: break
                ok,image=cap.read()
                if not ok:
                    if self.args.loop and cap.get(cv2.CAP_PROP_FRAME_COUNT)>0:
                        cap.set(cv2.CAP_PROP_POS_FRAMES,0); source_frame=0; continue
                    break
                fid+=1; source_frame+=1
                if (fid-1)%step: continue
                if not self.args.benchmark:
                    if self.stop.wait(max(0,due-time.monotonic())): break
                    due=max(due+step/fps,time.monotonic())
                self.process(fid,image,time.monotonic(),(source_frame-1)/fps)
        finally: cap.release()

    def live(self):
        from link import Link
        self.link=Link((self.args.bind,self.args.port),(self.args.peer,self.args.peer_port),self.publish,self.lookup,self.log)
        self.worker=threading.Thread(target=self.link.run,daemon=True); self.worker.start()
        consumed=None
        while not self.stop.wait(.005):
            if self.args.duration and time.monotonic()-self.started>=self.args.duration: break
            with self.lock: item=self.latest
            if item and item[0]!=consumed:
                consumed=item[0]; self.process(*item)

def parse():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--mode',choices=['FILE_TEST','LIVE_FRONT','SIMULATION'],required=True)
    p.add_argument('--video'); p.add_argument('--scene')
    p.add_argument('--output',default='runs/current'); p.add_argument('--web-port',type=int,default=8080)
    p.add_argument('--duration',type=float,default=0); p.add_argument('--max-frames',type=int,default=0)
    p.add_argument('--sample-fps',type=float,default=5); p.add_argument('--benchmark',action='store_true')
    p.add_argument('--loop',action='store_true',help='Replay FILE_TEST until Ctrl+C or --duration')
    p.add_argument('--snapshot-every',type=int,default=25)
    p.add_argument('--bind'); p.add_argument('--peer'); p.add_argument('--port',type=int,default=50000)
    p.add_argument('--peer-port',type=int,default=50000)
    p.add_argument('--link-config',help='JSON endpoint values; never changes OS networking')
    args=p.parse_args()
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
    if args.sample_fps<=0 or args.snapshot_every<1: p.error('sample-fps and snapshot-every must be positive')
    return args

if __name__=='__main__':
    app=App(parse())
    signal.signal(signal.SIGINT,lambda *_:app.stop.set())
    signal.signal(signal.SIGTERM,lambda *_:app.stop.set())
    app.run()
