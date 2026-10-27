"""Small temporal real-video audit; no timing-dependent production decisions.
Reference labels are external human observations. Throughput is not playback fps.
"""
import cv2,numpy as np,json,sys,bisect,copy,hashlib,time,importlib.util
from pathlib import Path
ROOT=Path(__file__).parent.parent
sys.path.append(str(ROOT/'m404'));sys.path.append(str(ROOT/'m403'))
from road import RoadModel
from lane_semantics import LaneSemantics
from detector import Detector
from legacy_perception import Perception
from driving import Driving
from overlay import draw
spec=importlib.util.spec_from_file_location('before_overlay',ROOT/'m405/overlay.py');before=importlib.util.module_from_spec(spec);spec.loader.exec_module(before)
cv2.setNumThreads(2)
CASES=[('develop','SC_BT.mp4',32),('develop','SC_BT.mp4',20),('develop','SC_BT2.mp4',12),('develop','SC_YJ.mp4',20),('develop','SC_YJ2.mp4',50),('holdout','SC_BT.mp4',45),('holdout','SC_BT.mp4',8),('holdout','SC_BT2.mp4',28),('holdout','SC_YJ.mp4',160),('holdout','SC_YJ2.mp4',65)]
if '--final' in sys.argv:
 CASES=[('develop','SC_BT.mp4',32),('final_holdout','SC_BT.mp4',26),('final_holdout','SC_BT.mp4',10),('final_holdout','SC_BT2.mp4',7),('final_holdout','SC_YJ.mp4',150),('final_holdout','SC_YJ2.mp4',39)]
base=ROOT/'m405r2/evidence'/('audit_final' if '--final' in sys.argv else 'audit');base.mkdir(parents=True,exist_ok=True)
scenes=json.loads((ROOT/'m403/scenes.json').read_text());model=RoadModel();det=Detector();rows=[]
for split,video,sec in CASES:
 pts=json.loads((ROOT/'m403'/(video+'.pts.json')).read_text());start=bisect.bisect_right(pts,sec-1.1)-1
 cap=cv2.VideoCapture(str(ROOT/'media'/video));cursor=start-1
 if video=='SC_YJ2.mp4':
  for _ in range(start):cap.grab()
 else:cap.set(cv2.CAP_PROP_POS_FRAMES,start)
 sem=LaneSemantics();temporal=[];driver=Driving();obs=None
 for at in np.linspace(sec-1,sec,9):
  idx=bisect.bisect_right(pts,float(at))-1
  while cursor<idx:
   assert cap.grab();cursor+=1
  ok,im=cap.retrieve();assert ok
  rd,masks=model.infer(im);raw=copy.deepcopy(rd)
  detection=det.detect(im,0,idx);sem.analyze(im,rd,masks,detection.get('objects'),float(pts[idx]))
  temporal.append(dict(pts=pts[idx],ego=rd['ego']['state'],semantics=rd['lane_semantics']))
 cap.release()
 # Real sample time is used above for deterministic temporal spacing. The age
 # clock below starts here solely for drawing this static audit snapshot.
 rd.update(state='DETECTED',source_frame_id=idx,age_ms=0,epoch=0,decoded_monotonic=time.monotonic());raw.update(state='DETECTED',source_frame_id=idx,age_ms=0,epoch=0)
 obs=Perception(scenes[video]).analyze(im);oldobs=copy.deepcopy(obs);oldobs['road']=raw;oldobs['detection']=copy.deepcopy(detection)
 obs['legacy_lanes']=obs['lanes'];obs['lanes']=rd['lane_semantics'];obs['road']=rd;obs['detection']=detection
 driver.command(dict(intent='right'),time.monotonic());drive=driver.update(obs,0,time.monotonic())
 name=video[:-4]+'_'+str(sec)
 cv2.imwrite(str(base/(name+'_raw.jpg')),im,[cv2.IMWRITE_JPEG_QUALITY,95]);cv2.imwrite(str(base/(name+'_before.jpg')),before.draw(im,oldobs,drive,640,video,pts[idx]));cv2.imwrite(str(base/(name+'_after.jpg')),draw(im,obs,drive,640,video,pts[idx]))
 for m,k in zip(masks,['road','paint']):cv2.imwrite(str(base/(name+'_'+k+'.png')),m)
 row=dict(split=split,video=video,pts=pts[idx],frame=idx,sha256_decoded=hashlib.sha256(im.tobytes()).hexdigest(),road=rd,driving=drive,temporal=temporal,scope='same native image, NPU segmentation, real distinct-frame temporal audit; not realtime fps')
 (base/(name+'.json')).write_text(json.dumps(row,ensure_ascii=False,indent=2))
 rows.append(dict(name=name,split=split,ego=rd['ego']['state'],left=rd['lane_semantics']['left']['state'],right=rd['lane_semantics']['right']['state'],adjacent=[rd['lane_semantics'][s]['adjacent']['state'] for s in ['left','right']]))
 print(rows[-1],flush=True)
model.close();det.close();(base/'index.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
