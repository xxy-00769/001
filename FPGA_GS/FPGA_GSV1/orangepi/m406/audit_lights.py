import sys,cv2,json,time
from pathlib import Path
from traffic import Lights
ROOT=Path(__file__).resolve().parents[1];out=ROOT/'m406/evidence/auto';out.mkdir(exist_ok=True);cv2.setNumThreads(2);rows=[];model=Lights()
for p in sorted((ROOT/'m406/evidence/proposals').glob('*_raw.jpg')):
 im=cv2.imread(str(p));model.reset()
 for k in range(2):r=model.analyze(im,0,k,time.monotonic())
 a=im.copy()
 for b in r['lights']:
  bb=list(map(int,b['box']));cv2.rectangle(a,tuple(bb[:2]),tuple(bb[2:]),(0,255,255),2);cv2.putText(a,str(b['id'])+':'+b['color'],tuple(bb[:2]),0,.7,(0,255,255),2)
 cv2.imwrite(str(out/p.name),cv2.resize(a,(1280,round(im.shape[0]*1280/im.shape[1]))));rows.append(dict(name=p.stem,result=r));print(p.stem,[(b['color'],b.get('body_score',b.get('confidence')),b['box'])for b in r['lights']],r['stage_ms'],flush=True)
(out/'results.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
model.close()
