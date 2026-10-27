import json,cv2,numpy as np
from pathlib import Path
from lane_semantics import LaneSemantics
p=Path(__file__).parent/'evidence/audit_final';s=LaneSemantics()
for n in ['SC_BT_32','SC_BT_26']:
 d=json.loads((p/(n+'.json')).read_text());e=d['road']['ego'];im=cv2.imread(str(p/(n+'_raw.jpg')));g=cv2.cvtColor(cv2.resize(im,(960,round(im.shape[0]*960/im.shape[1]))),cv2.COLOR_BGR2GRAY)
 c=cv2.morphologyEx(g,cv2.MORPH_TOPHAT,cv2.getStructuringElement(cv2.MORPH_RECT,(41,1)));paint=cv2.imread(str(p/(n+'_paint.png')),0)
 side='right';fit=np.asarray(e[side]['fit'])+(np.asarray(e['right']['fit'])-np.asarray(e['left']['fit']));lo=max(e[x]['ymin']for x in ['left','right']);hi=min(e[x]['ymax']for x in ['left','right'])
 r=s.evidence(dict(fit=fit.tolist(),ymin=lo,ymax=hi),g,c,paint,np.zeros_like(g),broad=True)
 if r:
  yy=np.linspace(max(lo,r['curve']['ymin']),min(hi,r['curve']['ymax']),20);dist=np.polyval(r['curve']['fit'],yy)-np.polyval(e['right']['fit'],yy)
  print(n,'coverage',r['evidence']['rgb_coverage'],'runs',r['evidence']['paint_runs'],'minwidth',dist.min(),'range',yy[0],yy[-1], 'history',[t['semantics']['right']['adjacent'].get('state') for t in d['temporal']])
 else:print(n,'no outer')
