"""COCO YOLOv8n / RK3588 NPU. Native-image xyxy, RGB letterbox input.
DFL and class-wise NMS follow Rockchip rknn_model_zoo (Apache-2.0).
No driving decisions depend on these detections.
"""
import time,collections,threading
from pathlib import Path
import cv2,numpy as np
NAMES={0:('person','行人'),1:('bicycle','自行车'),2:('car','汽车'),3:('motorcycle','摩托车'),5:('bus','客车'),7:('truck','货车')}

def iou(a,b):
 x=max(0,min(a[2],b[2])-max(a[0],b[0]));y=max(0,min(a[3],b[3])-max(a[1],b[1]))
 return x*y/max(1,(a[2]-a[0])*(a[3]-a[1])+(b[2]-b[0])*(b[3]-b[1])-x*y)

def prepare(image):
 h,w=image.shape[:2];scale=min(640/w,640/h);nw,nh=round(w*scale),round(h*scale)
 left=(640-nw)//2;top=(640-nh)//2
 out=np.full((640,640,3),114,np.uint8);out[top:top+nh,left:left+nw]=cv2.resize(image,(nw,nh))
 return cv2.cvtColor(out,cv2.COLOR_BGR2RGB)[None],(nw/w,nh/h,left,top)

def postprocess(outputs,transform,shape):
 boxes=[];classes=[];scores=[];pair=len(outputs)//3
 for branch in range(3):
  pos=outputs[branch*pair];prob=outputs[branch*pair+1];_,c,h,w=pos.shape
  # Select the model's best COCO class before restricting displayed classes.
  cls=prob.argmax(1)[0];score=prob.max(1)[0];mask=(score>=.25)&np.isin(cls,list(NAMES))
  ys,xs=np.where(mask)
  if not len(xs):continue
  p=pos[0,:,ys,xs].reshape(-1,4,c//4);p=np.exp(p-p.max(2,keepdims=True));d=(p/p.sum(2,keepdims=True)*np.arange(c//4)).sum(2)
  b=np.column_stack((xs+.5-d[:,0],ys+.5-d[:,1],xs+.5+d[:,2],ys+.5+d[:,3]))*(640/w)
  boxes.extend(b);classes.extend(cls[ys,xs]);scores.extend(score[ys,xs])
 if not boxes:return []
 boxes=np.array(boxes);classes=np.array(classes);scores=np.array(scores);keep=[]
 for cls in np.unique(classes):
  ids=np.where(classes==cls)[0];b=boxes[ids];xywh=np.column_stack((b[:,:2],b[:,2:]-b[:,:2])).tolist()
  selected=cv2.dnn.NMSBoxes(xywh,scores[ids].tolist(),.25,.45)
  if len(selected):keep.extend(ids[np.asarray(selected).reshape(-1)].tolist())
 sx,sy,l,t=transform;h,w=shape[:2];result=[]
 for i in sorted(keep,key=lambda i:-scores[i]):
  b=(boxes[i]-[l,t,l,t])/[sx,sy,sx,sy];b=np.clip(b,[0,0,0,0],[w,h,w,h]);cls=int(classes[i])
  if b[2]<=b[0] or b[3]<=b[1]:continue
  result.append(dict(class_id=cls,category=NAMES[cls][0],label=NAMES[cls][1],confidence=round(float(scores[i]),4),box=b.round(2).tolist(),source='detection'))
 return result

class Detector:
 def __init__(self):
  from rknnlite.api import RKNNLite
  self.r=RKNNLite();p=Path(__file__).resolve().parent/'yolov8n.rknn'
  if self.r.load_rknn(str(p))!=0:raise RuntimeError('RKNN模型加载失败')
  if self.r.init_runtime(core_mask=RKNNLite.NPU_CORE_0_1_2)!=0:raise RuntimeError('RKNN/NPU初始化失败')
  self.reset()
 def reset(self):self.tracks=[];self.next_id=1;self.stamps=collections.deque(maxlen=150)
 def detect(self,image,epoch,frame):
  t=time.perf_counter();tensor,tr=prepare(image);p=time.perf_counter()
  outputs=self.r.inference(inputs=[tensor]);q=time.perf_counter()
  if outputs is None:raise RuntimeError('NPU推理无输出')
  detections=postprocess(outputs,tr,image.shape);u=time.perf_counter();now=time.monotonic();used=set()
  for d in detections:
   options=[(iou(d['box'],x['box']),i) for i,x in enumerate(self.tracks) if i not in used and x['class_id']==d['class_id']]
   best=max(options,default=(0,-1))
   if best[0]>=.3:
    used.add(best[1]);d['track_id']=self.tracks[best[1]]['track_id']
   else:d['track_id']=self.next_id;self.next_id+=1
   d.update(last_detected_monotonic=now,missed=0,epoch=epoch,detection_frame_id=frame)
  # Briefly hold only one missed detection, <=120ms, explicitly distinct.
  held=[]
  for i,x in enumerate(self.tracks):
   if i not in used and x['missed']==0 and now-x['last_detected_monotonic']<=.12:
    held.append(dict(x,source='track_hold',missed=1,age_ms=round((now-x['last_detected_monotonic'])*1000,1)))
  self.tracks=detections+held;self.stamps.append(now);v=time.perf_counter()
  stamps=[x for x in self.stamps if now-x<5]
  return dict(backend='RKNN/NPU',model='YOLOv8n COCO w8a8',input_size=[640,640],threshold=.25,nms_iou=.45,epoch=epoch,frame_id=frame,
   objects=self.tracks,detected_count=len(detections),held_count=len(held),count=len(self.tracks),
   detection_fps=round((len(stamps)-1)/max(.001,now-stamps[0]),2) if len(stamps)>1 else 0,
   stage_ms=dict(det_preprocess=round((p-t)*1000,3),det_inference=round((q-p)*1000,3),det_postprocess=round((u-q)*1000,3),det_tracking=round((v-u)*1000,3)))
 def close(self):self.r.release()

class AsyncDetector:
 """One in-flight inference plus one replaceable latest-frame slot, never a queue."""
 def __init__(self):
  self.lock=threading.Lock();self.wake=threading.Event();self.stopping=False;self.pending=None;self.latest=None;self.error=None;self.epoch=-1
  self.completed=0;self.times=collections.deque(maxlen=150)
  self.thread=threading.Thread(target=self.run,name='npu-detection',daemon=True);self.thread.start()
 def reset(self,epoch):
  with self.lock:self.epoch=epoch;self.pending=None;self.latest=None;self.times.clear()
 def metrics(self):
  with self.lock:
   now=time.monotonic();stamps=[x for x in self.times if now-x<5]
   return dict(detection_runs=self.completed,detection_fps=round((len(stamps)-1)/max(.001,now-stamps[0]),2) if len(stamps)>1 else 0)
 def run(self):
  model=None;last_epoch=None
  try:
   model=Detector()
   while not self.stopping:
    self.wake.wait(.2);self.wake.clear()
    with self.lock:job=self.pending;self.pending=None
    if job is None:continue
    image,epoch,frame,decoded=job
    if epoch!=last_epoch:model.reset();last_epoch=epoch
    result=model.detect(image,epoch,frame)
    gray=cv2.cvtColor(cv2.resize(image,(640,360)),cv2.COLOR_BGR2GRAY)
    with self.lock:
     if epoch==self.epoch:self.latest=(result,gray,decoded,image.shape);self.completed+=1;self.times.append(time.monotonic())
  except Exception as e:self.error=repr(e)
  finally:
   if model:model.close()
 def update(self,image,epoch,frame,decoded):
  with self.lock:
   self.pending=(image,epoch,frame,decoded);latest=self.latest;self.wake.set()
  if self.error:raise RuntimeError('目标检测线程：'+self.error)
  if latest is None:return dict(backend='RKNN/NPU',objects=[],count=0,detected_count=0,held_count=0,detection_fps=0,stage_ms={},waiting=True)
  result,gray,at,shape=latest;age=time.monotonic()-at
  out=dict(result,objects=[],count=0,detected_count=0,held_count=0,inference_age_ms=round(age*1000,1),display_frame_id=frame)
  # Old results are never displayed across epochs, pause/seek, or >350ms age.
  if result['epoch']!=epoch or age>.35:return dict(out,expired=True)
  t=time.perf_counter();h,w=image.shape[:2];current=cv2.cvtColor(cv2.resize(image,(640,360)),cv2.COLOR_BGR2GRAY)
  points=[]
  for obj in result['objects']:
   x0,y0,x1,y1=np.array(obj['box'])*[640/w,360/h,640/w,360/h]
   points.extend([[(x0+x1)/2,(y0+y1)/2],[x0+(x1-x0)*.25,y0+(y1-y0)*.3],[x1-(x1-x0)*.25,y1-(y1-y0)*.3]])
  if points:
   pts=np.array(points,np.float32).reshape(-1,1,2)
   dest,ok,err=cv2.calcOpticalFlowPyrLK(gray,current,pts,None,winSize=(21,21),maxLevel=3)
  for i,obj in enumerate(result['objects']):
   if time.monotonic()-obj['last_detected_monotonic']>.35:continue
   b=np.array(obj['box']);good=(ok.reshape(-1)[i*3:i*3+3]>0)&(err.reshape(-1)[i*3:i*3+3]<30) if dest is not None else np.zeros(3,bool)
   if not good.any():continue
   shift=np.median((dest-pts).reshape(-1,2)[i*3:i*3+3][good],axis=0)*[w/640,h/360]
   if np.linalg.norm(shift/[w,h])>.15:continue
   box=np.clip(b+np.tile(shift,2),[0,0,0,0],[w,h,w,h]).round(2).tolist()
   source='detection' if result['frame_id']==frame and obj['source']=='detection' else 'optical_flow'
   out['objects'].append(dict(obj,box=box,source=source,age_ms=round(age*1000,1)))
  out['count']=len(out['objects']);out['detected_count']=sum(x['source']=='detection' for x in out['objects']);out['held_count']=out['count']-out['detected_count']
  out['stage_ms']=dict(result['stage_ms'],det_display_tracking=round((time.perf_counter()-t)*1000,3))
  return out
 def close(self):self.stopping=True;self.wake.set();self.thread.join(timeout=5)
