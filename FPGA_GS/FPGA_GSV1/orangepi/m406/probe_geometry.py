import cv2,numpy as np,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];out=ROOT/'m406/evidence/geometry';out.mkdir(exist_ok=True)
for p in (ROOT/'m406/evidence/proposals').glob('*_raw.jpg'):
 im=cv2.imread(str(p));h,w=im.shape[:2];a=cv2.resize(im,(1280,round(h*1280/w)));gray=cv2.cvtColor(a,cv2.COLOR_BGR2GRAY);hsv=cv2.cvtColor(a,cv2.COLOR_BGR2HSV)
 edge=cv2.Canny(gray,50,120);contours,_=cv2.findContours(edge,cv2.RETR_LIST,cv2.CHAIN_APPROX_SIMPLE);rows=[]
 for c in contours:
  x,y,bw,bh=cv2.boundingRect(c)
  if not(22<=bw<=160 and 8<=bh<=65 and 1.9<=bw/bh<=4.7 and y<a.shape[0]*.67 and cv2.contourArea(c)/(bw*bh)>.40):continue
  roi=hsv[y:y+bh,x:x+bw];mask=((roi[:,:,0]<18)|(roi[:,:,0]>165)|((roi[:,:,0]>35)&(roi[:,:,0]<95)))&(roi[:,:,1]>90)&(roi[:,:,2]>150)
  if mask.sum()<3:continue
  rows.append([x,y,bw,bh,float(cv2.contourArea(c)/(bw*bh)),int(mask.sum())]);cv2.rectangle(a,(x,y),(x+bw,y+bh),(0,255,255),1)
 cv2.imwrite(str(out/p.name),a);(out/(p.stem+'.json')).write_text(json.dumps(rows))
 print(p.stem,len(rows),flush=True)
