import cv2,numpy as np,json,sys,bisect,time,hashlib
from pathlib import Path
sys.path.append(str(Path(__file__).resolve().parents[1]/'m404'));sys.path.append(str(Path(__file__).resolve().parents[1]/'m403'))
from road import RoadModel
from detector import Detector
from perception import Perception
from driving import Driving
from overlay import draw
base=Path('m405/evidence/audit');base.mkdir(parents=True,exist_ok=True)
scenes=json.loads(Path('m403/scenes.json').read_text());model=RoadModel();det=Detector();rows=[]
for video,seconds in [('SC_BT.mp4',[5,20,32,57]),('SC_BT2.mp4',[3,12,25]),('SC_YJ.mp4',[5,20,72,98,130,170]),('SC_YJ2.mp4',[3,20,50,74])]:
 pts=json.loads((Path('m403')/(video+'.pts.json')).read_text())
 for sec in seconds:
  idx=bisect.bisect_right(pts,sec)-1;cap=cv2.VideoCapture('media/'+video)
  if video=='SC_YJ2.mp4':
   for _ in range(idx):cap.grab()
  else:cap.set(cv2.CAP_PROP_POS_FRAMES,idx)
  ok,im=cap.read();assert ok;cap.release();road,masks=model.infer(im);road.update(state='DETECTED',source_frame_id=idx,display_frame_id=idx,age_ms=0,epoch=0)
  p=Perception(scenes[video]);obs=p.analyze(im);obs['road']=road;obs['detection']=det.detect(im,0,idx);driver=Driving();d=driver.update(obs,0,time.monotonic());AsyncRoad=__import__('road').AsyncRoad;AsyncRoad.relate(None,obs['detection'],road,im.shape)
  name=video[:-4]+'_'+str(sec);cv2.imwrite(str(base/(name+'_raw.jpg')),im,[cv2.IMWRITE_JPEG_QUALITY,95]);cv2.imwrite(str(base/(name+'_overlay.jpg')),draw(im,obs,d,640,video,pts[idx]));cv2.imwrite(str(base/(name+'_road.png')),masks[0]);cv2.imwrite(str(base/(name+'_paint.png')),masks[1]);row=dict(video=video,pts=pts[idx],frame_id=idx,original_shape=list(im.shape),sha256_decoded=hashlib.sha256(im.tobytes()).hexdigest(),observation=obs,scope='same-frame direct NPU audit; not playback fps')
  (base/(name+'.json')).write_text(json.dumps(row,ensure_ascii=False,indent=2));rows.append(dict(video=video,pts=pts[idx],frame=idx,state=road['ego']['state'],reason=road['ego']['reason'],left=bool(road['ego'].get('left')),right=bool(road['ego'].get('right'))));print(rows[-1],flush=True)
model.close();det.close();(base/'index.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
