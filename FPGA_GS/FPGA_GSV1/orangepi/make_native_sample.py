"""Drop-only native-frame extraction to a bounded CFR720p sample, no interpolation."""
import argparse
import hashlib
import json
from pathlib import Path
import cv2

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('source'); p.add_argument('destination')
p.add_argument('--seconds',type=float,default=12)
p.add_argument('--max-fps',type=float,default=30)
a=p.parse_args()
dest=Path(a.destination)
if dest.exists(): p.error('Destination exists; preserve it and choose a new filename')
cap=cv2.VideoCapture(a.source)
if not cap.isOpened(): raise RuntimeError('Cannot open authorized source')
source_fps=cap.get(cv2.CAP_PROP_FPS)
if source_fps<=0: raise RuntimeError('Source reports invalid FPS')
fps=min(source_fps,a.max_fps,30)
writer=cv2.VideoWriter(str(dest),cv2.VideoWriter_fourcc(*'mp4v'),fps,(1280,720))
if not writer.isOpened(): raise RuntimeError('Video writer unavailable')
selected=[]; source_index=0; next_sample=0.; last_pts=-1.
try:
    while True:
        ok,image=cap.read()
        if not ok: break
        pts=cap.get(cv2.CAP_PROP_POS_MSEC)/1000
        if source_index>0 and pts<=last_pts: raise RuntimeError('Nonmonotonic source PTS; refuse fake CFR conversion')
        last_pts=pts
        if pts>=a.seconds: break
        if pts+1e-7>=next_sample:
            # Refuse missing source intervals rather than repeat a frame or speed up gaps.
            if pts-next_sample>1/fps+1e-5: raise RuntimeError('Source timestamp gap exceeds one output interval; VFR conversion required')
            writer.write(cv2.resize(image,(1280,720)))
            selected.append(dict(source_frame_index=source_index,source_seconds=pts,output_seconds=len(selected)/fps))
            next_sample=len(selected)/fps
        source_index+=1
finally: cap.release(); writer.release()
report=dict(mode='FILE_TEST',source=str(Path(a.source).resolve()),source_reported_fps=source_fps,
    sample_fps=fps,frames=len(selected),duration_seconds=len(selected)/fps,size=[1280,720],
    repeated_or_interpolated_frames=0,selected_native_frames=selected,
    source_sha256=hashlib.sha256(Path(a.source).read_bytes()).hexdigest(),
    sample_sha256=hashlib.sha256(dest.read_bytes()).hexdigest())
dest.with_suffix('.provenance.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k!='selected_native_frames'},indent=2))
