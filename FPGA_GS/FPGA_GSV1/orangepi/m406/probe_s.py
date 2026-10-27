import sys,json,cv2,numpy as np,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'m406/build_vendor'));sys.path.insert(0,str(ROOT/'m404'))
import types
sys.modules['requests']=types.ModuleType('requests')
from detector import prepare
import torch
torch.set_num_threads(2);ck=torch.load(ROOT/'m406/yolov8s.pt',weights_only=False,map_location='cpu');m=ck['model'].float().eval();print(type(m),flush=True)
out=ROOT/'m406/evidence/yolov8s';out.mkdir(exist_ok=True);rows=[]
for p in sorted((ROOT/'m406/evidence/proposals').glob('*_raw.jpg')):
 im=cv2.imread(str(p));h,w=im.shape[:2];ds=[]
 for scope,b in [('full',(0,0,w,h)),('left',(0,.15*h,.55*w,.65*h)),('right',(.45*w,.15*h,w,.65*h))]:
  x,y,x1,y1=map(int,b);a,(sx,sy,l,t)=prepare(im[y:y1,x:x1])
  with torch.no_grad():pr=m(torch.from_numpy(a.transpose(0,3,1,2).copy()).float()/255)[0][0].numpy().T
  score=pr[:,4:].max(1);classes=pr[:,4:].argmax(1);pr=pr[(classes==9)&(score>.20)];sc=score[(classes==9)&(score>.20)]
  if not len(pr):continue
  xy=np.column_stack((pr[:,0]-pr[:,2]/2,pr[:,1]-pr[:,3]/2,pr[:,2],pr[:,3]));ids=cv2.dnn.NMSBoxes(xy.tolist(),sc.tolist(),.20,.45)
  for j in np.asarray(ids).reshape(-1):
   xx,yy,bw,bh=xy[j];ds.append(dict(box=[(xx-l)/sx+x,(yy-t)/sy+y,(xx+bw-l)/sx+x,(yy+bh-t)/sy+y],confidence=float(sc[j]),scope=scope))
 a=im.copy()
 for d in ds:
  b=list(map(int,d['box']));cv2.rectangle(a,tuple(b[:2]),tuple(b[2:]),(0,255,255),2)
 cv2.imwrite(str(out/p.name),cv2.resize(a,(1280,round(h*1280/w))));rows.append(dict(name=p.stem,lights=ds));print(p.stem,ds,flush=True)
(out/'results.json').write_text(json.dumps(rows,indent=2))
