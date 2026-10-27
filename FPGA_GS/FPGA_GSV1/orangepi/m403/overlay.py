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
 def line(points,color,thick=3):cv2.polylines(out,[np.array(points,np.int32)],False,color,max(1,round(thick*s)))
 for side in ('left','right'):
  lane=obs['lanes'][side];trace=np.array(lane['trace']).reshape(-1,2)*[ww/w,hh/h]
  if len(trace) and lane['state']!='UNKNOWN':line(trace,(30,230,80) if lane['state']=='DASHED' else (0,210,255),3)
 sig=obs['signal']
 for c in sig.get('candidates',[]):
  x,y,bw,bh=np.array(c['box'])*[ww/w,hh/h,ww/w,hh/h];cv2.rectangle(out,(int(x)-4,int(y)-4),(int(x+bw)+4,int(y+bh)+4),(0,0,255) if c['state']=='RED' else (0,255,80),max(2,round(2*s)))
 if 'roi_pixels'in sig:
  x0,y0,x1,y1=(np.array(sig['roi_pixels'])*[ww/w,hh/h,ww/w,hh/h]).astype(int);cv2.rectangle(out,(x0,y0),(x1,y1),(255,220,100),1)
 # Three large directional arrows remain clear at 640px; the actual action is highlighted.
 for direction,cx in [('left',.39),('straight',.5),('right',.61)]:
  actual=drive['motion'];active=(direction=='left' and actual=='CHANGE_LEFT') or (direction=='right' and actual=='CHANGE_RIGHT') or (direction=='straight' and actual in ('MOVING','STRAIGHT'))
  color=(40,240,80) if active else (130,130,130);x=int(ww*cx);y=int(hh*.72)
  end=(x+int(ww*.055)*(-1 if direction=='left' else 1),y-int(hh*.04)) if direction!='straight' else (x,y-int(hh*.13))
  cv2.arrowedLine(out,(x,y),end,color,max(3,round(5*s)),tipLength=.4)
 if drive['motion']=='STOPPED':
  center=(int(ww*.88),int(hh*.66));r=int(23*s);pts=np.array([(center[0]+r*np.cos(a),center[1]+r*np.sin(a)) for a in np.arange(8)*np.pi/4+np.pi/8],np.int32);cv2.fillPoly(out,[pts],(30,30,220))
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
 text('灯色 '+STATE[sig['state']]+' / '+(directions+'·人工归属' if directions else '方向未标定'),8,hh/s-60,16)
 text('左 '+STATE[obs['lanes']['left']['state']]+'   右 '+STATE[obs['lanes']['right']['state']]+'  | '+drive['reason'][:29],8,hh/s-34,16)
 if drive['alarm']:text(drive['alarm']+' · 停车可解除',12,67,22,(255,255,255))
 if drive['motion']=='STOPPED':text('停',ww/s*.88-10,hh/s*.66-14,20)
 if sig.get('candidates'):
  box=sig['candidates'][0]['box'];x,y=box[0]/w*640,box[1]/h*(hh/s)
  text(STATE[sig['state']]+' '+directions+'(标定)',max(4,min(470,x-25)),max(100,y-22),14,(255,230,80))
 return cv2.cvtColor(np.array(pil),cv2.COLOR_RGB2BGR)
