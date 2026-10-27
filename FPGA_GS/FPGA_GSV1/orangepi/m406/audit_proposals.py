"""Real native images: evaluate pretrained body proposals, not color truth."""
import sys,json,cv2,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'m404'))
import detector
detector.NAMES[9]=('traffic light','交通灯')
cv2.setNumThreads(2)
out=ROOT/'m406/evidence/proposals';out.mkdir(parents=True,exist_ok=True)
model=detector.Detector();rows=[]
cases={'SC_BT.mp4':[5,8,12,35,55], 'SC_BT2.mp4':[5,15], 'SC_YJ.mp4':[65,85,99,103,105,107,120], 'SC_YJ2.mp4':[20,50]}
for video,times in cases.items():
 cap=cv2.VideoCapture(str(ROOT/'media'/video))
 for sec in times:
  cap.set(cv2.CAP_PROP_POS_MSEC,sec*1000);ok,im=cap.read()
  if not ok:continue
  h,w=im.shape[:2];name=video[:-4]+'_'+str(sec);cv2.imwrite(str(out/(name+'_raw.jpg')),im)
  proposals=[]
  # Generic center-upper crop, not a manually calibrated lamp ROI.
  for scope,box in [('full',(0,0,w,h)),('crop',(.20*w,.10*h,.80*w,.65*h))]:
   x0,y0,x1,y1=map(int,box);r=model.detect(im[y0:y1,x0:x1],0,sec)
   for d in r['objects']:
    if d['class_id']!=9 or d['source']!='detection':continue
    d=dict(d,box=[d['box'][0]+x0,d['box'][1]+y0,d['box'][2]+x0,d['box'][3]+y0],scope=scope);proposals.append(d)
  canvas=im.copy()
  for d in proposals:
   b=list(map(int,d['box']));cv2.rectangle(canvas,tuple(b[:2]),tuple(b[2:]),(0,255,255),3);cv2.putText(canvas,d['scope']+':%.2f'%d['confidence'],tuple(b[:2]),0,.8,(0,255,255),2)
  cv2.imwrite(str(out/(name+'_proposals.jpg')),cv2.resize(canvas,(1280,round(h*1280/w))))
  rows.append(dict(video=video,seconds=sec,size=[w,h],proposals=proposals));print(name,len(proposals),flush=True)
 cap.release()
(out/'results.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
model.close()
