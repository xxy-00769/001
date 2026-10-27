"""YOLOP road/paint segmentation, automatic ego-boundary selection. No manual ROI.
RKNN/NPU FP16 worker (ONNX CPU reference): one active input and one replaceable latest input. Normalized
contours/curves are display data, not lane instances or solid/dashed labels.
"""
import collections,threading,time,copy
from pathlib import Path
import cv2,numpy as np
from lane_semantics import LaneSemantics


def prepare(image,size,normalized=True):
 h,w=image.shape[:2];r=min(size/w,size/h);nw,nh=round(w*r),round(h*r);l=(size-nw)//2;t=(size-nh)//2
 rgb=np.full((size,size,3),114,np.uint8);rgb[t:t+nh,l:l+nw]=cv2.cvtColor(cv2.resize(image,(nw,nh)),cv2.COLOR_BGR2RGB)
 if not normalized:return rgb[None],(l,t,nw,nh)
 x=(rgb.astype(np.float32)/255.-np.array([.485,.456,.406],np.float32))/np.array([.229,.224,.225],np.float32)
 return x.transpose(2,0,1)[None],(l,t,nw,nh)

def contours(mask):
 # CCOMP retains holes (vehicles/people occlude visible road); no fixed trapezoid.
 cs,hi=cv2.findContours(mask,cv2.RETR_CCOMP,cv2.CHAIN_APPROX_SIMPLE);out=[]
 if hi is None:return out
 h,w=mask.shape
 for c,info in zip(cs,hi[0]):
  if cv2.contourArea(c)<4.5:continue
  pts=cv2.approxPolyDP(c,.6,True).reshape(-1,2)/[w,h]
  out.append(dict(points=pts.round(4).tolist(),hole=bool(info[3]>=0)))
 return out

def boundaries(lane,road):
 h,w=lane.shape;tracks=[]
 # Model-paint run centres, joined upward with gap and curvature limits.
 for y in range(int(h*.94),int(h*.44),-max(2,h//90)):
  row=np.any(lane[max(0,y-1):y+2]>0,axis=0);edges=np.diff(np.r_[False,row,False].astype(np.int8));xs=[]
  for a,b in zip(np.where(edges==1)[0],np.where(edges==-1)[0]):
   if 1<=b-a<=w*.055:xs.append((a+b-1)/2)
  used=set()
  for x in xs:
   opts=[]
   for i,tr in enumerate(tracks):
    if i in used or tr[-1][1]-y>h*.16:continue
    pred=tr[-1][0]
    if len(tr)>2:
     dx=(tr[-1][0]-tr[-3][0])/(tr[-1][1]-tr[-3][1]);pred+=np.clip(dx,-2,2)*(y-tr[-1][1])
    d=abs(x-pred)
    if d<w*.032+(tr[-1][1]-y)*.45:opts.append((d,i))
   if opts:
    _,i=min(opts);tracks[i].append((x,y));used.add(i)
   else:tracks.append([(x,y)]);used.add(len(tracks)-1)
 candidates=[]
 for tr in tracks:
  a=np.asarray(tr,dtype=float)/[w,h]
  if len(a)<7 or np.ptp(a[:,1])<.16:continue
  fit=np.polyfit(a[:,1],a[:,0],2);err=float(np.sqrt(np.mean((np.polyval(fit,a[:,1])-a[:,0])**2)))
  if err>.022 or a[:,1].max()<.68:continue
  ys=np.linspace(a[:,1].min(),a[:,1].max(),30);xs=np.polyval(fit,ys)
  if (xs<0).any() or (xs>1).any():continue
  # Require some road beside paint; paint alone on buildings/guardrails isn't enough.
  iy=np.clip((ys*h).astype(int),0,h-1);ix=np.clip((xs*w).astype(int),0,w-1)
  support=float(np.mean([np.any(road[y,max(0,x-int(w*.04)):min(w,x+int(w*.04)+1)]) for x,y in zip(ix,iy)]))
  if support<.65:continue
  candidates.append(dict(points=np.c_[xs,ys].round(4).tolist(),fit=fit.tolist(),ymin=float(ys[0]),ymax=float(ys[-1]),error=round(err,4),road_support=round(support,3)))
 # Optical axis (x=.5) is an explicit default camera assumption, not a lane polygon.
 anchor=.76;left=[];right=[]
 for c in candidates:
  if not(c['ymin']<=anchor<=c['ymax']+.025):continue
  x=float(np.polyval(c['fit'],anchor))
  if x<.49:left.append((x,c))
  elif x>.51:right.append((x,c))
 l=max(left,key=lambda a:a[0])[1] if left else None;r=min(right,key=lambda a:a[0])[1] if right else None
 result=dict(left=l,right=r,state='UNKNOWN',reason='左右边界不足；不推造完整本车道',polygon=[],candidates=candidates,camera_assumption='光轴中心x=0.5；未作车辆外参标定')
 if not(l and r):return result
 lo=max(l['ymin'],r['ymin']);hi=min(l['ymax'],r['ymax']);ys=np.linspace(lo,hi,35);lx=np.polyval(l['fit'],ys);rx=np.polyval(r['fit'],ys);width=rx-lx
 # Perspective naturally converges at the horizon; trim a too-narrow far tip
 # instead of rejecting a correct near-field lane. No extrapolated coordinates.
 valid=(width>.025)&(width<.88)
 if not valid[-1]:result['reason']='近场边界交叉或车道宽度不合理';return result
 start=len(valid)-1
 while start>0 and valid[start-1]:start-=1
 ys=ys[start:];lx=lx[start:];rx=rx[start:]
 if len(ys)<2 or ys[-1]-ys[0]<.15 or (rx[-1]-lx[-1])<.12:result['reason']='共同可观察边界太短/过窄';return result
 # Visible road evidence at the path centre. Missing road under an occluding car
 # does not truncate the fitted boundaries. It lowers evidence, not a road endpoint.
 mx=np.clip(((lx+rx)*.5*w).astype(int),0,w-1);my=np.clip((ys*h).astype(int),0,h-1);support=float(np.mean(road[my,mx]>0))
 if support<.42:result['reason']='本车前方道路支持不足/遮挡';return result
 result.update(state='DETECTED',reason='模型车道线＋道路支持；自动选择光轴两侧最近边界',polygon=np.r_[np.c_[lx,ys],np.c_[rx,ys][::-1]].round(4).tolist(),path_road_support=round(support,3))
 return result

class RoadModel:
 def __init__(self,backend='rknn'):
  self.backend=backend;self.size=320
  if backend=='rknn':
   from rknnlite.api import RKNNLite
   self.r=RKNNLite()
   if self.r.load_rknn(str(Path(__file__).parent.parent/'m405'/'yolop320_fp16.rknn'))!=0:raise RuntimeError('道路RKNN模型加载失败')
   if self.r.init_runtime(core_mask=RKNNLite.NPU_CORE_0_1_2)!=0:raise RuntimeError('道路NPU初始化失败')
  else:
   import onnxruntime as ort
   opt=ort.SessionOptions();opt.intra_op_num_threads=3;opt.inter_op_num_threads=1;opt.execution_mode=ort.ExecutionMode.ORT_SEQUENTIAL
   self.session=ort.InferenceSession(str(Path(__file__).parent.parent/'m405'/'yolop320.onnx'),opt,providers=['CPUExecutionProvider'])
 def close(self):
  if self.backend=='rknn':self.r.release()
 def infer(self,image):
  t=time.perf_counter();x,(l,top,w,h)=prepare(image,self.size,self.backend!='rknn');a=time.perf_counter()
  outputs=self.r.inference(inputs=[x]) if self.backend=='rknn' else self.session.run(['drive_area_seg','lane_line_seg'],{'images':x});b=time.perf_counter()
  masks=[]
  for output in outputs:
   binary=output[0].argmax(0).astype('uint8')[top:top+h,l:l+w]
   masks.append(cv2.resize(binary,(320,180),interpolation=cv2.INTER_NEAREST)*255)
  rawroad,paint=masks
  # Retain all sufficiently large road components connected to lower half; no
  # colour thresholds or scene-specific coordinates supply the segmentation.
  n,labels,stats,_=cv2.connectedComponentsWithStats(rawroad,8);road=np.zeros_like(rawroad)
  for i in range(1,n):
   if stats[i,cv2.CC_STAT_AREA]>25 and stats[i,cv2.CC_STAT_TOP]+stats[i,cv2.CC_STAT_HEIGHT]>95:road[labels==i]=255
  ego=boundaries(paint,road);c=time.perf_counter()
  return dict(road_contours=contours(road),paint_contours=contours(paint),ego=ego,stage_ms=dict(road_preprocess=round(1000*(a-t),2),road_model=round(1000*(b-a),2),lane_postprocess=round(1000*(c-b),2))),masks

class AsyncRoad:
 def __init__(self):
  self.cv=threading.Condition();self.pending=None;self.result=None;self.epoch=0;self.stop=False;self.stamps=collections.deque(maxlen=90);self.completed=0;self.replaced=0;self.error=None;self.semantic=LaneSemantics()
  self.worker=threading.Thread(target=self.run,name='road-onnx',daemon=True);self.worker.start()
 def reset(self,epoch):
  with self.cv:self.epoch=epoch;self.pending=None;self.result=None;self.stamps.clear()
 def metrics(self):
  with self.cv:
   now=time.monotonic();ts=[t for t in self.stamps if now-t<5];return dict(model='YOLOP',backend='RKNN/NPU FP16',target_fps=8,semantic_update_fps=round((len(ts)-1)/max(.001,now-ts[0]),2) if len(ts)>1 else 0,semantic_target_fps=8,input_size=320,outputs=['drivable_area','binary_lane_paint'],completed=self.completed,update_fps=round((len(ts)-1)/max(.001,now-ts[0]),2) if len(ts)>1 else 0,replaced_pending=self.replaced,error=self.error,alive=self.worker.is_alive())
 def run(self):
  try:
   model=RoadModel();next_due=0
   while True:
    with self.cv:
     self.cv.wait_for(lambda:self.stop or self.pending is not None)
     if self.stop:model.close();return
     while not self.stop and time.monotonic()<next_due:self.cv.wait(timeout=next_due-time.monotonic())
     if self.stop:model.close();return
     if self.pending is None:continue
     im,epoch,frame,decoded,boxes=self.pending;self.pending=None;next_due=time.monotonic()+1/8
    result,masks=model.infer(im);now=time.monotonic()
    if getattr(self,'semantic_epoch',None)!=epoch:self.semantic.reset();self.semantic_epoch=epoch
    self.semantic.analyze(im,result,masks,boxes,now)
    # Veto a sudden lane switch once; never carry an old lane into a new epoch.
    with self.cv:previous=self.result if epoch==self.epoch else None
    if previous and previous.get('epoch')==epoch and now-previous['decoded_monotonic']<.5 and result['ego']['state']=='DETECTED' and previous['ego']['state']=='DETECTED':
     jump=max(abs(np.polyval(result['ego'][side]['fit'],.72)-np.polyval(previous['ego'][side]['fit'],.72)) for side in ('left','right'))
     if jump>.12:result['ego'].update(state='UNKNOWN',polygon=[],reason='边界位置突变，等待下一次独立模型确认')
    result.update(epoch=epoch,source_frame_id=frame,decoded_monotonic=decoded,completed_monotonic=now)
    with self.cv:
     if epoch==self.epoch:self.result=result;self.completed+=1;self.stamps.append(now)
  except Exception as e:
   with self.cv:self.error=repr(e)
 def update(self,image,epoch,frame,decoded,boxes=None):
  with self.cv:
   if epoch!=self.epoch:self.epoch=epoch;self.result=None;self.pending=None
   if self.pending is not None:self.replaced+=1
   self.pending=(image,epoch,frame,decoded,copy.deepcopy(boxes or []));self.cv.notify()
   r=self.result
   if r is None or r['epoch']!=epoch:return dict(state='UNKNOWN',reason=self.error or '道路模型等待首个结果',ego=dict(state='UNKNOWN',reason='等待当前周期模型',left=None,right=None,polygon=[]),age_ms=None)
   age=time.monotonic()-r['decoded_monotonic']
   if age>.5:return dict(state='UNKNOWN',reason='道路模型证据超过500ms失效',ego=dict(state='UNKNOWN',reason='道路模型过期',left=None,right=None,polygon=[]),age_ms=round(age*1000,1),source_frame_id=r['source_frame_id'])
   result=copy.deepcopy(r);result.update(state='DETECTED' if frame==r['source_frame_id'] else 'HELD',age_ms=round(age*1000,1),display_frame_id=frame)
   # No optical warp is claimed for these held masks. Short reuse is explicit.
   result['ego']['display_source']='direct' if frame==r['source_frame_id'] else 'short_hold';return result
 def relate(self,detection,road,shape):
  ego=road.get('ego',{});l=ego.get('left');r=ego.get('right');h,w=shape[:2]
  for obj in detection.get('objects',[]):
   obj['spatial_relation']='UNKNOWN';obj['spatial_reason']='本车道未知或目标底点超出边界观测范围'
   if ego.get('state')!='DETECTED' or not(l and r) or road.get('age_ms',999)>250 or obj.get('age_ms',0)>250:continue
   x=(obj['box'][0]+obj['box'][2])/(2*w);y=obj['box'][3]/h
   if not(max(l['ymin'],r['ymin'])<=y<=min(l['ymax'],r['ymax'])):continue
   a=float(np.polyval(l['fit'],y));b=float(np.polyval(r['fit'],y));margin=.015
   relation='FRONT' if a+margin<x<b-margin else 'LEFT' if x<a-margin else 'RIGHT' if x>b+margin else 'UNKNOWN'
   obj.update(spatial_relation=relation,spatial_reason='目标底部中心与新鲜本车道边界比较；非占道/碰撞判定',relation_road_frame=road.get('source_frame_id'))
 def close(self):
  with self.cv:self.stop=True;self.cv.notify_all()
  self.worker.join(timeout=8)
