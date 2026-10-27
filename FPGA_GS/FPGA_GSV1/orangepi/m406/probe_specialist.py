import sys,time,json,cv2,numpy as np
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'m404'))
from detector import prepare
from rknnlite.api import RKNNLite
cv2.setNumThreads(2);r=RKNNLite();assert r.load_rknn(str(ROOT/'m406/tlony640_fp16.rknn'))==0;assert r.init_runtime(core_mask=RKNNLite.NPU_CORE_0)==0
names=json.loads((ROOT/'m406/classes.json').read_text());out=ROOT/'m406/evidence/specialist';out.mkdir(exist_ok=True)
rows=[]
for p in sorted((ROOT/'m406/evidence/proposals').glob('*_raw.jpg')):
 im=cv2.imread(str(p));h,w=im.shape[:2];all=[]
 for scope,box in [('full',(0,0,w,h)),('upper',(0,.20*h,w,.60*h))]:
  x0,y0,x1,y1=map(int,box);tensor,(sx,sy,l,t)=prepare(im[y0:y1,x0:x1]);at=time.perf_counter();pred=r.inference(inputs=[tensor])[0][0].T;elapsed=(time.perf_counter()-at)*1000
  cls=pred[:,4:].argmax(1);score=pred[:,4:].max(1);p0=pred[score>=.18];cs=cls[score>=.18];sc=score[score>=.18]
  if not len(p0):continue
  b=np.column_stack((p0[:,0]-p0[:,2]/2,p0[:,1]-p0[:,3]/2,p0[:,2],p0[:,3]))
  ids=cv2.dnn.NMSBoxes(b.tolist(),sc.tolist(),.18,.45)
  for i in np.asarray(ids).reshape(-1):
   xx,yy,bw,bh=b[i];bb=[(xx-l)/sx+x0,(yy-t)/sy+y0,(xx+bw-l)/sx+x0,(yy+bh-t)/sy+y0]
   all.append(dict(box=bb,label=names[str(cs[i])],confidence=float(sc[i]),scope=scope,inference_ms=elapsed))
 canvas=im.copy()
 for d in all:
  b=list(map(int,d['box']));cv2.rectangle(canvas,tuple(b[:2]),tuple(b[2:]),(0,255,255),2);cv2.putText(canvas,d['label']+' %.2f'%d['confidence'],tuple(b[:2]),0,.7,(0,255,255),2)
 cv2.imwrite(str(out/p.name.replace('_raw','_specialist')),cv2.resize(canvas,(1280,round(h*1280/w))))
 rows.append(dict(name=p.stem,objects=all));print(p.stem,[(d['label'],round(d['confidence'],2),d['scope'])for d in all],flush=True)
(out/'results.json').write_text(json.dumps(rows,indent=2));r.release()
