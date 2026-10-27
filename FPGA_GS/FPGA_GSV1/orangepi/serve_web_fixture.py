"""Test-only gated FILE_TEST for real browser first-frame/error/recovery checks.

Creates no production test API and never opens UDP. Marker files live only in
the explicitly supplied output directory. All decoded frames still use App.file.
"""
import argparse
import json
import signal
import threading
import time
from pathlib import Path
from types import SimpleNamespace
from main import App

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--video',required=True); p.add_argument('--scene',required=True)
p.add_argument('--output',required=True); p.add_argument('--web-port',type=int,default=8081)
p.add_argument('--duration',type=float,default=240)
a=p.parse_args(); out=Path(a.output); out.mkdir(parents=True,exist_ok=True)
app=App(SimpleNamespace(mode='FILE_TEST',scene=a.scene,output=a.output,web_port=a.web_port,
    video=a.video,sample_fps=5,benchmark=False,loop=True,duration=a.duration,max_frames=0,snapshot_every=25))
signal.signal(signal.SIGINT,lambda *_:app.stop.set())
signal.signal(signal.SIGTERM,lambda *_:app.stop.set())
original=app.process
def gated_process(*args):
    if (out/'pause').exists():
        with app.lock: app.jpeg=None; app.raw_jpeg=None
        while (out/'pause').exists() and not app.stop.wait(.02): pass
    if not app.stop.is_set(): original(*args)
app.process=gated_process
worker=None
try:
    app.preview()
    print(json.dumps(dict(fixture=True,mode='FILE_TEST',port=a.web_port)),flush=True)
    while not app.stop.wait(.02):
        if (out/'stop').exists() or time.monotonic()-app.started>=a.duration: break
        if worker is None and (out/'start').exists():
            worker=threading.Thread(target=app.file,daemon=True); worker.start()
finally:
    app.stop.set()
    if worker: worker.join(timeout=3)
    if app.server: app.server.shutdown(); app.server.server_close()
    (out/'fixture_summary.json').write_text(json.dumps(app.status(),ensure_ascii=False,indent=2),encoding='utf-8')
    app.logfile.close()
