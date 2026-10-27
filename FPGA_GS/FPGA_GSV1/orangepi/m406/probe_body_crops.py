import sys,cv2,json,numpy as np
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'m404'))
import detector
detector.NAMES[9]=('traffic light','交通灯');m=detector.Detector()
im=cv2.imread(str(ROOT/'m406/evidence/proposals/SC_YJ_99_raw.jpg'))
for b in [(1450,560,1790,725),(1400,450,2000,900),(0,300,1279,950),(1279,300,2558,950)]:
 x,y,x1,y1=b;r=m.detect(im[y:y1,x:x1],0,0);print(b,[(d['class_id'],d['box'],d['confidence'])for d in r['objects']if d['source']=='detection'],flush=True)
m.close()
