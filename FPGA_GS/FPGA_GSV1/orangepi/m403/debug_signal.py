import cv2,json
from pathlib import Path
root=Path(__file__).resolve().parent
im=cv2.imread(str(root/'evidence/YJ_scene_105.jpg'))
crop=im[610:710,1540:1770];cv2.imwrite(str(root/'evidence/green_native_crop.png'),cv2.resize(crop,None,fx=4,fy=4))
im=im[627:668,1638:1719];hsv=cv2.cvtColor(im,cv2.COLOR_BGR2HSV)
mask=cv2.inRange(hsv,(38,95,175),(98,255,255));out=[]
for c in cv2.findContours(mask,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)[0]:
 x,y,w,h=cv2.boundingRect(c);a=cv2.contourArea(c);r=max(w,h);cx=x+w//2;cy=y+h//2
 v=hsv[max(0,cy-r):min(im.shape[0],cy+r+1),max(0,cx-r):min(im.shape[1],cx+3*r),2]
 out.append(dict(box=[x,y,w,h],area=a,ratio=w/h,fill=a/(w*h),dark=float((v<110).mean())))
print(json.dumps(out))
from perception import Perception
cfg=json.loads((root/'scenes.json').read_text())['SC_YJ.mp4'];p=Perception(cfg)
cap=cv2.VideoCapture(str(root.parent/'media/SC_YJ.mp4'));cap.set(cv2.CAP_PROP_POS_MSEC,105000)
ok,im=cap.read();print('DIRECT',json.dumps(p.signal(im),ensure_ascii=False))
cv2.imwrite(str(root/'evidence/green_direct.png'),cv2.resize(im[627:668,1638:1719],None,fx=8,fy=8))
hsv=cv2.cvtColor(im[627:668,1638:1719],cv2.COLOR_BGR2HSV);mask=cv2.inRange(hsv,(38,95,175),(98,255,255));print('DIRECT_CONTOURS',[(cv2.boundingRect(c),cv2.contourArea(c)) for c in cv2.findContours(mask,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)[0]])
