"""Automatic image-only capsule signal baseline. No scene/time/ROI truth.

Specialist TLoNY and COCO failed local Chinese horizontal housings (see audit).
This constrained CPU fallback requires a capsule rim, dark multi-lens housing,
one compact chromatic emitter, and temporal confirmation. It is not a general
traffic-light neural model, nor a controller-assignment or arrow classifier.
"""
import cv2,numpy as np,time,threading,collections,copy,base64
from pathlib import Path

CN={'RED':'红','YELLOW':'黄','GREEN':'绿','UNKNOWN':'不可判','OFF':'熄灭'}

def dense_context(image,box):
 x0,y0,x1,y1=map(int,box);h,w=image.shape[:2];bw=x1-x0;bh=y1-y0
 p=image[max(0,y0-bh):min(h,y1+bh),max(0,x0-bw):min(w,x1+bw)]
 if not p.size:return True,{}
 hsv=cv2.cvtColor(p,cv2.COLOR_BGR2HSV);edge=cv2.Canny(cv2.cvtColor(p,cv2.COLOR_BGR2GRAY),50,120)
 density=float(np.mean(edge>0));saturation=float(np.mean((hsv[:,:,1]>80)&(hsv[:,:,2]>100)))
 return density>.19 or saturation>.6,dict(edge_fraction=round(density,4),saturated_fraction=round(saturation,4),source='密集文字/LED背景后处理否决，非模型精度')

def overlap(a,b):
 x=max(0,min(a[2],b[2])-max(a[0],b[0]));y=max(0,min(a[3],b[3])-max(a[1],b[1]))
 return x*y/max(1,(a[2]-a[0])*(a[3]-a[1])+(b[2]-b[0])*(b[3]-b[1])-x*y)

def body_score(gray,cx,cy,d,index,vertical):
 # Three circular lens positions inside a rounded rectangular signal housing.
 # Evaluate all emitter slots, both orientations and size hypotheses, not ROIs.
 bw,bh=3.65*d,1.40*d;x=cx-(.70+1.125*index)*d;y=cy-.70*d
 if vertical:x,y=cx-.70*d,cy-(.70+1.125*index)*d;bw,bh=bh,bw
 h,w=gray.shape;x0,y0,x1,y1=map(int,(x,y,x+bw,y+bh))
 if x0<2 or y0<2 or x1>=w-2 or y1>=h-2 or min(x1-x0,y1-y0)<7:return None
 patch=cv2.resize(gray[y0:y1,x0:x1],(18,48) if vertical else (48,18))
 if vertical:patch=patch.T
 # Long sides are sampled independently; streetlight pairs cannot pass merely
 # by having a bright color and a dark background.
 top=patch[0:5].max(0).astype(float);bottom=patch[-5:].max(0).astype(float)
 inner=patch[6:12].mean(0);xs=np.r_[14:21,27:34]
 rim=np.minimum(top[xs],bottom[xs])-inner[xs]
 coverage=float(np.mean(rim>18));contrast=float(np.median(rim))
 # Closed end caps need contrast as well, preventing poles/text from passing.
 ends=(float(patch[4:14,:5].max(1).mean())+float(patch[4:14,-5:].max(1).mean()))/2
 dark=float(np.median(patch[6:12,8:40]));dark_fraction=float(np.mean(patch[5:13,7:41]<100))
 if coverage<.5 or contrast<14 or ends-dark<10 or dark_fraction<.47:return None
 return (coverage+min(contrast,90)/90+min(ends-dark,80)/80)/3,[x0,y0,x1,y1],dict(rim_coverage=round(coverage,3),rim_contrast=round(contrast,2),dark_fraction=round(dark_fraction,3))

def candidates(image,objects=()):
 h,w=image.shape[:2];scale=min(1,1280/w);a=cv2.resize(image,(round(w*scale),round(h*scale)));hh,ww=a.shape[:2]
 hsv=cv2.cvtColor(a,cv2.COLOR_BGR2HSV);gray=cv2.cvtColor(a,cv2.COLOR_BGR2GRAY);hu,sa,va=cv2.split(hsv)
 colors={'RED':((hu<14)|(hu>168)), 'YELLOW':((hu>=14)&(hu<35)), 'GREEN':((hu>=38)&(hu<99))}
 found=[];tested=0
 for state,condition in colors.items():
  mask=(condition&(sa>105)&(va>150)).astype(np.uint8)*255
  # A broad upper-image search is an explicit scope restriction, not a scene ROI.
  mask[int(hh*.66):]=0;count,labels,stats,centers=cv2.connectedComponentsWithStats(mask)
  ids=[i for i in range(1,count) if 4<=stats[i,4]<=260 and 2<=min(stats[i,2:4]) and max(stats[i,2:4])<=28 and max(stats[i,2:4])/min(stats[i,2:4])<2.8]
  # Bounded bright proposals; no unrestricted image tiling or per-pixel inference.
  ids=sorted(ids,key=lambda i:-stats[i,4])[:12]
  for i in ids:
   cx,cy=centers[i];x,y,bw,bh,area=stats[i];radius=max(2,np.sqrt(area/np.pi));best=None
   if any(b['box'][0]*scale<=cx<=b['box'][2]*scale and b['box'][1]*scale<=cy<=b['box'][3]*scale for b in objects):continue
   for factor in (1.05,1.35,1.7,2.15):
    d=radius*2*factor
    if d<4 or d>28:continue
    for vertical in (False,):
     for index in ((0,) if state=='RED' else (2,) if state=='GREEN' else (1,)):
      result=body_score(gray,cx,cy,d,index,vertical);tested+=1
      if result and (best is None or result[0]>best[0]):best=(*result,vertical,index,d)
   if best:
    score,box,ev,vertical,index,d=best
    found.append(dict(box=(np.array(box)/scale).round(2).tolist(),color=state,color_evidence='原图紧致发光区HSV + 胶囊灯壳/暗腔复查',body_source='AUTO_CAPSULE_GEOMETRY',body_score=round(score,3),evidence=dict(ev,emitter_pixels=int(area),slot=index,orientation='vertical' if vertical else 'horizontal'),shape='UNKNOWN',shape_reason='发光区太小或眩光；圆灯/箭头不可可靠区分',direction='UNKNOWN',control_relation='UNKNOWN',control_reason='未建立灯组与本车请求方向归属',confidence=None))
 # Isolated geometry is too error-prone. Only aligned, similarly sized paired
 # three-lens horizontal housings survive this restricted fallback.
 paired=[]
 for a in found:
  aa=a['box'];aw=aa[2]-aa[0];ah=aa[3]-aa[1];ax=(aa[0]+aa[2])/2;ay=(aa[1]+aa[3])/2
  for b in found:
   if b is a:continue
   bb=b['box'];bw=bb[2]-bb[0];bh=bb[3]-bb[1];bx=(bb[0]+bb[2])/2;by=(bb[1]+bb[3])/2
   if .6<aw/bw<1.65 and .6<ah/bh<1.65 and abs(ay-by)<max(ah,bh)*.8 and 1.4<abs(ax-bx)/max(aw,bw)<4.5 and min(a['body_score'],b['body_score'])>.42:
    a['evidence']['paired_housing']=True;paired.append(a);break
 paired.sort(key=lambda b:-b['body_score']);keep=[]
 for b in paired:
  if not any(overlap(b['box'],a['box'])>.25 for a in keep):keep.append(b)
 return keep[:6],dict(raw_geometry_candidates=len(found),paired_geometry_candidates=len(keep),geometry_hypotheses=tested)

class BodyModel:
 def __init__(self):
  from rknnlite.api import RKNNLite
  self.r=RKNNLite();assert self.r.load_rknn(str(Path(__file__).parent/'yolov8s640_fp16.rknn'))==0
  assert self.r.init_runtime(core_mask=RKNNLite.NPU_CORE_2)==0
  self.turn=0
 def infer(self,image):
  h,w=image.shape[:2];items=[];stage=collections.defaultdict(float)
  # Two fixed generic upper-image half crops, no learned or manual lamp ROI.
  scans=[(0,int(.12*h),int(.55*w),int(.66*h)),(int(.45*w),int(.12*h),w,int(.66*h))];scanned=scans[self.turn%2];self.turn+=1
  for x0,y0,x1,y1 in [scanned]:
   a=image[y0:y1,x0:x1];hh,ww=a.shape[:2];scale=min(640/ww,640/hh);nw,nh=round(ww*scale),round(hh*scale);l,t=(640-nw)//2,(640-nh)//2
   at=time.perf_counter();tensor=np.full((640,640,3),114,np.uint8);tensor[t:t+nh,l:l+nw]=cv2.resize(a,(nw,nh));tensor=cv2.cvtColor(tensor,cv2.COLOR_BGR2RGB)[None];p=time.perf_counter()
   outputs=self.r.inference(inputs=[tensor]);q=time.perf_counter()
   if outputs is None:raise RuntimeError('交通灯NPU无输出')
   pred=outputs[0][0].T;cls=pred[:,4:].argmax(1);scores=pred[:,4:].max(1);ok=(cls==9)&(scores>=.25);pred=pred[ok];scores=scores[ok]
   if len(pred):
    boxes=np.column_stack((pred[:,0]-pred[:,2]/2,pred[:,1]-pred[:,3]/2,pred[:,2],pred[:,3]));ids=cv2.dnn.NMSBoxes(boxes.tolist(),scores.tolist(),.25,.45)
    for i in np.asarray(ids).reshape(-1):
     x,y,bw,bh=boxes[i];box=np.clip([(x-l)/(nw/ww)+x0,(y-t)/(nh/hh)+y0,(x+bw-l)/(nw/ww)+x0,(y+bh-t)/(nh/hh)+y0],[0,0,0,0],[w,h,w,h]).tolist()
     if box[2]-box[0]<5 or box[3]-box[1]<5:continue
     items.append(dict(box=box,confidence=round(float(scores[i]),4),body_source='YOLOv8s_COCO_class9_RKNN_FP16'))
   stage['traffic_preprocess']+=(p-at)*1000;stage['traffic_inference']+=(q-p)*1000;stage['traffic_postprocess']+=(time.perf_counter()-q)*1000
  items.sort(key=lambda b:-b['confidence']);keep=[]
  for b in items:
   if not any(overlap(b['box'],a['box'])>.3 for a in keep):keep.append(b)
  return keep,dict(stage),scanned
 def close(self):self.r.release()

def color_check(image,b):
 x0,y0,x1,y1=map(int,b['box']);roi=image[y0:y1,x0:x1];h,w=roi.shape[:2]
 row=dict(b,color='UNKNOWN',shape='UNKNOWN',shape_reason='灯型或分辨率/眩光证据不足',direction='UNKNOWN',kind='UNKNOWN',control_relation='UNKNOWN',control_reason='机动车/行人类别及本车方向归属未确认',reason='灯体候选；灯区无可靠颜色证据')
 if b.get('confidence') is not None and b['confidence']<.45:row['reason']='灯体模型低置信度，仅保留候选；不输出确定灯色';return row
 if x0<=4 or x1>=image.shape[1]-4:row['reason']='灯体被画面边缘截断，不能把倒计时或部分灯体当完整信号';return row
 if min(h,w)<6:return row
 if b['body_source'].startswith('AUTO_CAPSULE'):
  # The verified three-lens horizontal casing supplies physical lens cells.
  # Read CURRENT RGB inside each cell; cell position alone is never a color.
  # This recovers chromatic rims around clipped-white night emitters without
  # mistaking the neighboring flag/counter for the active light.
  blue,green,red=cv2.split(roi.astype(np.float32));yy,xx=np.mgrid[:h,:w];cell_evidence={};options=[]
  for state,cx,cond in [('RED',.192,(red>180)&(red>green*1.25)&(red>blue*1.4)),('YELLOW',.5,(red>180)&(green>150)&(green>red*.82)&(blue<green*.7)),('GREEN',.808,(green>160)&(green>red*1.2)&(green>blue*.92))]:
   cell=((xx-cx*w)**2+(yy-.5*h)**2)<(.34*h)**2;count=int(np.sum(cell&cond));cell_evidence[state]=count
   if count>=max(3,int(cell.sum()*.025)):options.append((count,state))
  row['lamp_cell_evidence']=dict(rgb_support_pixels=cell_evidence,layout='自动成对横排暗壳；标准红黄绿三灯位假设，非人工ROI')
  options.sort(reverse=True)
  if options and (len(options)==1 or options[1][0]<options[0][0]*.4):
   row.update(color=options[0][1],reason='当前原图灯位内有对应RGB发光证据；控制关系未知',color_evidence='暗壳三灯位 + 当前RGB色边缘；白色过曝核心不参与定色');return row
  if options:row['reason']='多个灯位有近似发光证据，灯态冲突';return row
 hsv=cv2.cvtColor(roi,cv2.COLOR_BGR2HSV);hu,sa,va=cv2.split(hsv)
 if np.median(va)>150:row['reason']='候选外壳不暗，可能为招牌/反光';return row
 candidates0=[]
 for name,cond in [('RED',(hu<12)|(hu>168)),('YELLOW',(hu>=22)&(hu<35)),('GREEN',(hu>=38)&(hu<99))]:
  mask=(cond&(sa>90)&(va>130)).astype(np.uint8)*255
  cs,_=cv2.findContours(mask,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
  for c in cs:
   xx,yy,bw,bh=cv2.boundingRect(c);area=cv2.contourArea(c)
   if area<2 or bw*bh>roi.shape[0]*roi.shape[1]*.45 or max(bw,bh)/max(1,min(bw,bh))>2.5:continue
   perimeter=cv2.arcLength(c,True);circularity=4*np.pi*area/max(1,perimeter**2)
   if circularity>.35 and area/(bw*bh)>.35:candidates0.append((area,name,(xx,yy,bw,bh),float(circularity)))
 if not candidates0:return row
 candidates0.sort(reverse=True);area,state,component,circularity=candidates0[0]
 # Ambiguous multi-color candidates are not one global state; glare orange is
 # not coerced to red. Preserve the raw evidence in the structured result.
 other=max((x[0]for x in candidates0 if x[1]!=state),default=0)
 if other>area*.65:row['reason']='同一候选中多色接近，眩光或多个灯态不明';return row
 xx,yy,bw,bh=component
 row.update(color=state,reason='原图灯区颜色复查；灯组控制关系未知',color_evidence=dict(component_pixels=area,component_box=[xx,yy,bw,bh],circularity=round(circularity,3)))
 if min(bw,bh)>=8 and .8<bw/bh<1.25 and circularity>.78 and np.mean(va[yy:yy+bh,xx:xx+bw]>245)<.15:
  row.update(shape='CIRCLE',shape_reason='原图足够分辨、紧致近圆发光轮廓；箭头未支持')
 return row

class Lights:
 def __init__(self,neural=True):self.model=BodyModel() if neural else None;self.reset()
 def reset(self):
  self.tracks=[];self.patches={};self.next_id=1;self.transitions=collections.deque(maxlen=10)
  if self.model:self.model.turn=0
 def analyze(self,image,epoch,frame,decoded,objects=()):
  start=time.perf_counter();items,stats=candidates(image,objects);filtered=[];rejected=0
  for b in items:
   veto,context=dense_context(image,b['box'])
   if veto:rejected+=1;continue
   b['context_evidence']=context;filtered.append(color_check(image,b))
  items=filtered;stats['dense_context_rejected']=rejected;now=time.monotonic()
  # Short image-based housing tracking starts only from automatic paired
  # housings. Match the current raw pixels, reclassify color on this frame,
  # and expire after 1.2s without an independent geometry detection. No manual
  # template, static scene coordinates or old lamp color is ever used.
  for old in self.tracks:
   ref=self.patches.get(old['id'])
   if not ref or now-ref['direct_at']>1.2 or any(overlap(old['box'],b['box'])>.25 for b in items):continue
   x0,y0,x1,y1=map(int,old['box']);pad=max(5,int((y1-y0)*.5));xx=max(0,x0-pad);yy=max(0,y0-pad);xx1=min(image.shape[1],x1+pad);yy1=min(image.shape[0],y1+pad)
   search=cv2.cvtColor(image[yy:yy1,xx:xx1],cv2.COLOR_BGR2GRAY);template=ref['patch']
   if min(search.shape)<1 or search.shape[0]<template.shape[0] or search.shape[1]<template.shape[1]:continue
   match=cv2.matchTemplate(search,template,cv2.TM_CCOEFF_NORMED);_,score,_,loc=cv2.minMaxLoc(match)
   if score<.88:continue
   bx,by=xx+loc[0],yy+loc[1];bh,bw=template.shape
   veto,context=dense_context(image,[bx,by,bx+bw,by+bh])
   if veto:stats['dense_context_rejected']+=1;continue
   b=dict(box=[bx,by,bx+bw,by+bh],body_source='AUTO_CAPSULE_IMAGE_TRACK',body_score=old.get('body_score'),tracking_match=round(score,4),origin_frame_id=ref['frame'],confidence=None,context_evidence=context)
   items.append(color_check(image,b))
  geom_ms=(time.perf_counter()-start)*1000;stages={}
  if self.model:
   proposals,stages,scanned=self.model.infer(image)
   for p in proposals:
    if not any(overlap(p['box'],o['box'])>.3 for o in objects) and not any(overlap(p['box'],o['box'])>.25 for o in items):items.append(color_check(image,p))
  now=time.monotonic();used=set();out=[]
  for b in items:
   opts=[(overlap(b['box'],t['box']),j)for j,t in enumerate(self.tracks)if j not in used and now-t['seen_at']<.65]
   score,j=max(opts,default=(0,-1))
   old=self.tracks[j] if score>.3 else None
   if old:used.add(j);ident=old['id'];hits=old['hits']+1
   else:ident=self.next_id;self.next_id+=1;hits=1
   # A new/changed color is immediately UNKNOWN until two consecutive direct
   # observations. Never carry old red or green through a transition.
   streak=old.get('streak',0)+1 if old and old['observed_color']==b['color'] else 1
   color=b['color'] if streak>=2 and hits>=2 else 'UNKNOWN'
   last_confirmed=(old or {}).get('last_confirmed','UNKNOWN')
   change=None
   if color!='UNKNOWN' and last_confirmed not in ('UNKNOWN',color):
    change=dict(id=ident,previous=last_confirmed,current=color,frame_id=frame,at_monotonic=now);self.transitions.append(change)
   if color!='UNKNOWN':last_confirmed=color
   x0,y0,x1,y1=map(int,b['box']);roi=image[max(0,y0-3):min(image.shape[0],y1+3),max(0,x0-3):min(image.shape[1],x1+3)]
   thumb=base64.b64encode(cv2.imencode('.jpg',roi,[cv2.IMWRITE_JPEG_QUALITY,85])[1]).decode() if roi.size else None
   stamps=[t for t in (old or {}).get('observation_times',[]) if now-t<5]+[now]
   row=dict(b,id=ident,hits=hits,streak=streak,observed_color=b['color'],color=color,last_confirmed=last_confirmed,seen_at=now,source_frame_id=frame,epoch=epoch,decoded_monotonic=decoded,source='IMAGE_BODY_TRACK' if b['body_source']=='AUTO_CAPSULE_IMAGE_TRACK' else 'DIRECT_IMAGE',reason='灯色已识别，控制关系未知' if color!='UNKNOWN' else b.get('reason','新灯体或灯态变化，等待连续图像确认'),change=change,thumbnail_jpeg=thumb,observation_times=stamps,update_fps=round((len(stamps)-1)/max(.001,stamps[-1]-stamps[0]),2)if len(stamps)>1 else 0)
   if b['body_source']=='AUTO_CAPSULE_GEOMETRY':
    x0,y0,x1,y1=map(int,b['box']);patch=cv2.cvtColor(image[y0:y1,x0:x1],cv2.COLOR_BGR2GRAY)
    if patch.size and patch.std()>10:self.patches[ident]=dict(patch=patch,direct_at=now,frame=frame)
   out.append(row)
  # The other half is scanned on the next observation. Retain its last direct
  # body for <=600ms with original source frame/time, explicitly marked HELD.
  if self.model:
   for j,t in enumerate(self.tracks):
    cx=(t['box'][0]+t['box'][2])/2;cy=(t['box'][1]+t['box'][3])/2
    if j not in used and t['body_source'].startswith('YOLO') and not(scanned[0]<=cx<=scanned[2] and scanned[1]<=cy<=scanned[3]) and now-t['decoded_monotonic']<.6:
     out.append(dict(t,source='TEMPORAL_HOLD'))
  # Geometry-only missed bodies are not emitted as lights. Keep association
  # memory briefly but never draw a previous lamp or color without evidence.
  ids={t['id']for t in out};self.tracks=out+[t for t in self.tracks if t['id'] not in ids and now-t['seen_at']<.5]
  self.patches={i:p for i,p in self.patches.items() if i in {t['id']for t in self.tracks} and now-p['direct_at']<=1.2}
  return dict(backend='RKNN/NPU + CPU',method='YOLOv8s COCO灯体 + 成对横排灯壳几何 + 原图灯色 + 两次时序确认',scope='上方66%画面；箭头/机动车与行人灯区分及控制归属未完成',epoch=epoch,source_frame_id=frame,decoded_monotonic=decoded,age_ms=0,lights=out,transitions=list(self.transitions),control_relation='UNKNOWN',control_reason='自动归属未实现；不使用旧人工场景标定',stage_ms=dict(stages,traffic_geometry_color=round(geom_ms,3),traffic_total=round((time.perf_counter()-start)*1000,3)),statistics=stats)
 def close(self):
  if self.model:self.model.close()

def fresh(result,now,epoch=None):
 out=copy.deepcopy(result) if result else dict(lights=[],transitions=[],reason='等待交通灯图像证据')
 age=(now-out.get('decoded_monotonic',-1e9))*1000;out['age_ms']=round(age,1) if result else None
 if not result or age>600 or (epoch is not None and out.get('epoch')!=epoch):
  out['lights']=[];out['transitions']=[];out['expired']=True;out['reason']='交通灯证据超过600ms或播放周期已变化' if result else '等待首次交通灯检测'
 else:
  out['lights']=[dict(b,age_ms=round((now-b.get('decoded_monotonic',-1e9))*1000,1))for b in out.get('lights',[]) if now-b.get('decoded_monotonic',-1e9)<=.6]
 return out

class AsyncLights:
 def __init__(self):
  self.lock=threading.Lock();self.wake=threading.Event();self.stop=False;self.pending=None;self.latest=None;self.epoch=-1;self.error=None;self.completed=0;self.skipped=0;self.sampling_skipped=0;self.pending_replaced=0;self.last_submit=0;self.times=collections.deque(maxlen=120)
  self.thread=threading.Thread(target=self.run,name='traffic-lights',daemon=True);self.thread.start()
 def reset(self,epoch):
  with self.lock:self.epoch=epoch;self.pending=None;self.latest=None;self.times.clear();self.last_submit=0
 def run(self):
  try:model=Lights()
  except Exception as e:self.error=repr(e);return
  epoch0=None
  while not self.stop:
   self.wake.wait(.2);self.wake.clear()
   with self.lock:job=self.pending;self.pending=None
   if job is None:continue
   image,epoch,frame,decoded,objects=job
   if epoch!=epoch0:model.reset();epoch0=epoch
   try:result=model.analyze(image,epoch,frame,decoded,objects)
   except Exception as e:self.error=repr(e);continue
   with self.lock:
    if epoch==self.epoch:self.latest=result;self.completed+=1;self.times.append(time.monotonic())
  model.close()
 def update(self,image,epoch,frame,decoded,objects):
  with self.lock:
   if decoded-self.last_submit>=.25:
    if self.pending:self.skipped+=1;self.pending_replaced+=1
    self.pending=(image,epoch,frame,decoded,objects);self.last_submit=decoded;self.wake.set()
   else:self.skipped+=1;self.sampling_skipped+=1
   return fresh(self.latest,time.monotonic(),epoch)
 def metrics(self):
  with self.lock:
   now=time.monotonic();ts=[t for t in self.times if now-t<5]
   return dict(target_hz=4,update_fps=round((len(ts)-1)/max(.001,now-ts[0]),2)if len(ts)>1 else 0,completed=self.completed,skipped_source_observations=self.skipped,sampling_skipped=self.sampling_skipped,pending_replaced=self.pending_replaced,neural_region_schedule='左右半图交替，每侧约总观测率的一半；逐灯update_fps单列',error=self.error,thread_alive=self.thread.is_alive())
 def close(self):self.stop=True;self.wake.set();self.thread.join(5)
