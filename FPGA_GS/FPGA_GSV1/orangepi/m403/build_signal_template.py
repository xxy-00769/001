"""Explicit manual lamp housing calibration from a documented original image."""
import cv2,pathlib,json,numpy as np
r=pathlib.Path(__file__).resolve().parents[1];out=r/'m403/evidence';p=out/'SC_YJ_71.13.jpg';im=cv2.imread(str(p))
# Native source pixels, selected by visual inspection of the physical horizontal housing.
box=[1638,627,1719,668];x0,y0,x1,y1=box
template=cv2.cvtColor(im[y0:y1,x0:x1],cv2.COLOR_BGR2GRAY)
cv2.imwrite(str(r/'m403/signal_housing.png'),template)
mask=np.ones_like(template,np.uint8)*255;mask[9:34,12:78]=0
cv2.imwrite(str(r/'m403/signal_housing_mask.png'),mask)
results=[]
for path in list(out.glob('YJ_scene_*.jpg'))+list(out.glob('SC_YJ_*.jpg')):
 if 'overlay'in path.name or 'contact'in path.name:continue
 im=cv2.imread(str(path));h,w=im.shape[:2];roi=[int(.625*w),int(.425*h),int(.68*w),int(.48*h)];a,b,c,d=roi
 crop=cv2.cvtColor(im[b:d,a:c],cv2.COLOR_BGR2GRAY)
 result=cv2.matchTemplate(crop,template,cv2.TM_CCORR_NORMED,mask=mask);result=np.nan_to_num(result,nan=0,posinf=0,neginf=0);_,maxscore,_,point=cv2.minMaxLoc(result)
 results.append(dict(file=path.name,score=maxscore,point=point));print(path.name,round(maxscore,3),point)
(out/'signal_template_calibration.json').write_text(json.dumps(dict(source=p.name,source_original='SC_YJ.mp4',source_seconds=71.13,box_native=box,method='manual geometry template; color classified on current pixels, not template',scores=results),indent=2))
