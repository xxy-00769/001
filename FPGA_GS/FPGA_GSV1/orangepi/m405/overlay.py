"""Readable annotations in the delivered JPEG, not just HTML text."""
import cv2,numpy as np
from PIL import Image,ImageDraw,ImageFont
from functools import lru_cache
from pathlib import Path

FONT=next((str(p) for p in [Path('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc'),Path('/usr/share/fonts/opentype/noto/NotoSerifCJK-Bold.ttc')] if p.exists()),'/usr/share/fonts/truetype/arphic/uming.ttc')
@lru_cache(maxsize=32)
def font(size):return ImageFont.truetype(FONT,size)
@lru_cache(maxsize=384)
def tile(text,size,color):
 f=font(size);bbox=f.getbbox(text);im=Image.new('RGBA',(bbox[2]+4,size+9),(0,0,0,0));ImageDraw.Draw(im).text((2,0),text,font=f,fill=(*color,255));return im
STATE={'UNKNOWN':'未知','RED':'红灯','GREEN':'绿灯','SOLID':'实线','DASHED':'虚线'}
MOTION={'STOPPED':'模拟停车','MOVING':'模拟行驶','STRAIGHT':'模拟直行','CHANGE_LEFT':'模拟左变道','CHANGE_RIGHT':'模拟右变道'}
INTENT={'auto':'自动','straight':'直行','left':'左','right':'右','stop':'停车'}
def draw(image,obs,drive,width,video,sec):
 h,w=image.shape[:2];out=cv2.resize(image,(width,round(h*width/w)),interpolation=cv2.INTER_LINEAR);hh,ww=out.shape[:2];s=width/640
 # Road mask is model output in normalized image coordinates, blended before boxes.
 road=obs.get('road',{});ego=road.get('ego',{});mask=np.zeros((hh,ww),np.uint8)
 if obs.get('show_road',True):
  for c in road.get('road_contours',[]):
   pts=(np.asarray(c['points'])*[ww,hh]).astype(np.int32);cv2.fillPoly(mask,[pts],0 if c['hole'] else 255)
  tinted=np.empty_like(out);tinted[:]=(170,140,30);cv2.copyTo(cv2.addWeighted(out,.77,tinted,.23,0),mask,out)
 if obs.get('show_lane',True):
  poly=ego.get('polygon',[])
  if poly:
   lane_mask=np.zeros((hh,ww),np.uint8);cv2.fillPoly(lane_mask,[(np.asarray(poly)*[ww,hh]).astype(np.int32)],255)
   # Geometric ego area spans visible occlusions; it is not a free-space guarantee.
   tinted=np.empty_like(out);tinted[:]=(50,220,80);cv2.copyTo(cv2.addWeighted(out,.76,tinted,.24,0),lane_mask,out)
  for side in ('left','right'):
   edge=ego.get(side)
   if edge:
    pts=(np.asarray(edge['points'])*[ww,hh]).astype(np.int32)
    if ego.get('state')=='DETECTED':cv2.polylines(out,[pts],False,(0,255,220) if road.get('state')=='DETECTED' else (0,190,255),max(2,round(3*s)))
    else:
     for i in range(0,len(pts)-1,2):cv2.line(out,tuple(pts[i]),tuple(pts[i+1]),(220,200,100),max(1,round(2*s)))
 def line(points,color,thick=3):cv2.polylines(out,[np.array(points,np.int32)],False,color,max(1,round(thick*s)))
 for side in ('left','right'):
  lane=obs['lanes'][side];trace=np.array(lane['trace']).reshape(-1,2)*[ww/w,hh/h]
  if False and len(trace) and lane['state']!='UNKNOWN':line(trace,(30,230,80) if lane['state']=='DASHED' else (0,210,255),3)
 sig=obs['signal']
 for c in sig.get('candidates',[]):
  x,y,bw,bh=np.array(c['box'])*[ww/w,hh/h,ww/w,hh/h];cv2.rectangle(out,(int(x)-4,int(y)-4),(int(x+bw)+4,int(y+bh)+4),(0,0,255) if c['state']=='RED' else (0,255,80),max(2,round(2*s)))
 if 'roi_pixels'in sig:
  x0,y0,x1,y1=(np.array(sig['roi_pixels'])*[ww/w,hh/h,ww/w,hh/h]).astype(int);cv2.rectangle(out,(x0,y0),(x1,y1),(255,220,100),1)
 # Human/vehicle model outputs use native-image coordinates; labels avoid driving panels.
 targets=[]
 for obj in obs.get('detection',{}).get('objects',[]):
  x0,y0,x1,y1=(np.array(obj['box'])*[ww/w,hh/h,ww/w,hh/h]).astype(int)
  color=(255,190,30) if obj['class_id']==0 else (80,240,100)
  tracked=obj['source']!='detection'
  if tracked:
   for xx in range(x0,x1,max(1,int(12*s))):
    cv2.line(out,(xx,y0),(min(x1,xx+int(7*s)),y0),color,max(1,int(2*s)));cv2.line(out,(xx,y1),(min(x1,xx+int(7*s)),y1),color,max(1,int(2*s)))
   cv2.line(out,(x0,y0),(x0,y1),color,max(1,int(s)));cv2.line(out,(x1,y0),(x1,y1),color,max(1,int(s)))
  else:cv2.rectangle(out,(x0,y0),(x1,y1),color,max(1,int(2*s)))
  targets.append((obj,max(0,min(ww-int(150*s),x0)),max(int(100*s),min(hh-int(82*s),y0-int(20*s)))))
 # Three large directional arrows remain clear at 640px; the actual action is highlighted.
 for direction,cx in [('left',.08),('straight',.17),('right',.26)]:
  actual=drive['motion'];active=(direction=='left' and actual=='CHANGE_LEFT') or (direction=='right' and actual=='CHANGE_RIGHT') or (direction=='straight' and actual in ('MOVING','STRAIGHT'))
  color=(40,240,80) if active else (130,130,130);x=int(ww*cx);y=int(hh*.78)
  end=(x+int(ww*.055)*(-1 if direction=='left' else 1),y-int(hh*.04)) if direction!='straight' else (x,y-int(hh*.13))
  cv2.arrowedLine(out,(x,y),end,color,max(3,round(5*s)),tipLength=.4)
 if drive['motion']=='STOPPED':
  center=(int(ww*.93),int(hh*.29));r=int(23*s);pts=np.array([(center[0]+r*np.cos(a),center[1]+r*np.sin(a)) for a in np.arange(8)*np.pi/4+np.pi/8],np.int32);cv2.fillPoly(out,[pts],(30,30,220))
 # Dark panels have bounded height and avoid the horizon/lamps.
 cv2.rectangle(out,(0,0),(ww,int(65*s)),(18,24,31),-1)
 cv2.rectangle(out,(0,hh-int(62*s)),(ww,hh),(18,24,31),-1)
 if drive['alarm']:cv2.rectangle(out,(3,3),(ww-4,hh-4),(0,0,255),max(4,int(5*s)));cv2.rectangle(out,(0,int(65*s)),(ww,int(97*s)),(20,20,200),-1)
 pil=Image.fromarray(cv2.cvtColor(out,cv2.COLOR_BGR2RGB))
 def text(t,x,y,size=17,color=(245,245,245)):
  im=tile(t,round(size*s),color);pil.paste(im,(round(x*s),round(y*s)),im)
 text('本地录像 / 模拟车辆 · '+video,8,2,15,(130,220,255))
 text(f'{MOTION[drive["motion"]]}   请求：{INTENT[drive["intent"]]}'+('（强制）' if drive['forced'] else ''),8,24,21,(255,220,90))
 text(f'{int(sec)//60:02d}:{int(sec)%60:02d}',555,26,18,(170,200,220))
 directions='、'.join({'left':'左转','straight':'直行','right':'右转'}[a] for a in sig.get('actions',[]))
 occupied=[]
 for obj,tx,ty in targets:
  label=obj['label']+{'FRONT':'·前方','LEFT':'·左侧','RIGHT':'·右侧','UNKNOWN':'·不明'}.get(obj.get('spatial_relation','UNKNOWN'),'')+' '+str(round(obj['confidence']*100))+'%'+('·续' if obj['source']!='detection' else '')
  im=tile(label,round(13*s),(255,255,255))
  for delta in [0,-18,18,-36,36,-54,54]:
   yy=max(round(100*s),min(hh-round(82*s),ty+round(delta*s)));bb=(tx,yy,tx+im.width,yy+im.height)
   if not any(bb[0]<a[2] and bb[2]>a[0] and bb[1]<a[3] and bb[3]>a[1] for a in occupied):ty=yy;break
  occupied.append((tx,ty,tx+im.width,ty+im.height))
  bg=Image.new('RGBA',im.size,(0,0,0,210));bg.alpha_composite(im);pil.paste(bg,(tx,ty),bg)
 det=obs.get('detection',{});text('NPU 人车',360,3,13,(140,255,170))
 text(('本车道 '+('自动边界' if ego.get('state')=='DETECTED' else '未知')+' · '+('短时沿用' if road.get('state')=='HELD' else '当前检测')),8,hh/s-60,15)
 # Legacy calibrated traffic light and line-type rules remain separate.
 if False:text('灯色 '+STATE[sig['state']]+' / '+(directions+'·人工归属' if directions else '方向未标定'),8,hh/s-60,16)
 text(('左 '+(('检测' if road.get('state')=='DETECTED' else '推测') if ego.get('left') and ego.get('state')=='DETECTED' else '候选' if ego.get('left') else '未知')+' / 右 '+(('检测' if road.get('state')=='DETECTED' else '推测') if ego.get('right') and ego.get('state')=='DETECTED' else '候选' if ego.get('right') else '未知')+' · '+ego.get('reason','等待道路模型')[:28]),8,hh/s-34,14)
 if drive['alarm']:text(drive['alarm']+' · 停车可解除',12,67,22,(255,255,255))
 if drive['motion']=='STOPPED':text('停',ww/s*.93-10,hh/s*.29-14,20)
 if sig.get('candidates'):
  box=sig['candidates'][0]['box'];x,y=box[0]/w*640,box[1]/h*(hh/s)
  text(STATE[sig['state']]+' '+directions+'(标定)',max(4,min(470,x-25)),max(100,y-22),14,(255,230,80))
 out=cv2.cvtColor(np.array(pil),cv2.COLOR_RGB2BGR)
 # Fast numeric glyphs avoid rebuilding a CJK text tile for every changing age/fps.
 age=road.get('age_ms');age_label=('age %.0fms'%age) if age is not None else 'age --'
 cv2.putText(out,age_label,(round(500*s),hh-round(44*s)),cv2.FONT_HERSHEY_SIMPLEX,.43*s,(190,220,250),max(1,round(s)),cv2.LINE_AA)
 cv2.putText(out,str(det.get('count',0))+' | '+str(det.get('detection_fps',0))+'fps',(round(425*s),round(18*s)),cv2.FONT_HERSHEY_SIMPLEX,.40*s,(170,255,140),max(1,round(s)),cv2.LINE_AA)
 return out
