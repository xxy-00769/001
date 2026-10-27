import cv2,json,numpy as np
from pathlib import Path
base=Path(__file__).parent/'evidence/exact_source';im=cv2.imread(str(base/'GREEN_raw.jpg'));h,w=im.shape[:2]
for b in json.loads((base/'GREEN.json').read_text())['lights']:
 x0,y0,x1,y1=map(int,b['box']);bw=x1-x0;bh=y1-y0;p=im[max(0,y0-bh):min(h,y1+bh),max(0,x0-bw):min(w,x1+bw)];hsv=cv2.cvtColor(p,cv2.COLOR_BGR2HSV);edge=cv2.Canny(cv2.cvtColor(p,cv2.COLOR_BGR2GRAY),50,120)
 print(b['id'],b['color'],'saturated',np.mean((hsv[:,:,1]>80)&(hsv[:,:,2]>100)),'edge',np.mean(edge>0),'bright',np.mean(hsv[:,:,2]>180))
