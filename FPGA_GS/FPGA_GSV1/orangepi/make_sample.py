"""Extract a bounded, unlabelled FILE_TEST clip from the authorized video."""
import argparse
from pathlib import Path
import cv2

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('source'); p.add_argument('destination'); p.add_argument('--seconds',type=float,default=16)
a=p.parse_args()
if Path(a.destination).exists(): p.error('Destination already exists; choose a new filename')
cap=cv2.VideoCapture(a.source)
if not cap.isOpened(): raise RuntimeError('Cannot open authorized source')
fps=cap.get(cv2.CAP_PROP_FPS) or 25
out=cv2.VideoWriter(a.destination,cv2.VideoWriter_fourcc(*'mp4v'),5,(1280,720))
if not out.isOpened(): raise RuntimeError('Video writer unavailable')
next_sample=0.; count=0; fid=0
while fid/fps<a.seconds:
    ok,image=cap.read()
    if not ok: break
    if fid/fps>=next_sample:
        out.write(cv2.resize(image,(1280,720))); count+=1; next_sample+=.2
    fid+=1
cap.release(); out.release()
print(dict(mode='FILE_TEST',source=a.source,frames=count,sample_fps=5,seconds=count/5))
