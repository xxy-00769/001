"""M4-03 CPU image evidence. Spatial calibration never encodes a label or time range."""
import collections,time
from pathlib import Path
import cv2,numpy as np

def runs(a):
 e=np.diff(np.r_[False,a,False].astype(np.int8));return list(zip(np.where(e==1)[0],np.where(e==-1)[0]))

class Perception:
 def __init__(self,scene):
  self.scene=scene;self.votes={k:collections.deque(maxlen=5) for k in ('signal','left','right')};self.geometry={}
  cfg=scene.get('signal') or {};base=Path(__file__).resolve().parent
  self.template=cv2.imread(str(base/cfg['template']),0) if cfg.get('template') else None
  self.template_mask=cv2.imread(str(base/cfg['mask']),0) if cfg.get('mask') else None
  cv2.setNumThreads(2)
 def stable(self,name,raw):
  q=self.votes[name];q.append(raw)
  if raw=='UNKNOWN':return 'UNKNOWN'
  if name=='signal':return raw if len(q)>=3 and list(q)[-3:]==[raw]*3 else 'UNKNOWN'
  # Dashed paint naturally enters/leaves a finite image strip while moving.
  # Require current image evidence plus 3 same-type observations within 5 frames;
  # any opposite line type vetoes. Never substitute a vote for unknown pixels.
  opposite='DASHED' if raw=='SOLID' else 'SOLID'
  return raw if list(q).count(raw)>=3 and opposite not in q else 'UNKNOWN'
 def signal(self,image):
  cfg=self.scene.get('signal');unknown=dict(state='UNKNOWN',raw_state='UNKNOWN',confidence=0,actions=[],candidates=[],reason='未标定相关灯组；不能将任意彩灯归属本车道')
  if not cfg:return unknown
  h,w=image.shape[:2];box=np.clip(np.array(cfg['roi']),0,1);x0,y0,x1,y1=(box*[w,h,w,h]).astype(int)
  crop=image[y0:y1,x0:x1]
  if crop.size==0:return unknown
  match_score=None
  if self.template is not None:
   th,tw=self.template.shape
   if crop.shape[0]<th or crop.shape[1]<tw:return dict(unknown,reason='灯体外壳超出标定区域',actions=cfg.get('actions',[]))
   gray=cv2.cvtColor(crop,cv2.COLOR_BGR2GRAY)
   scores=cv2.matchTemplate(gray,self.template,cv2.TM_CCORR_NORMED,mask=self.template_mask)
   scores=np.nan_to_num(scores,nan=0,posinf=0,neginf=0);_,match_score,_,point=cv2.minMaxLoc(scores)
   if match_score<.85:
    self.stable('signal','UNKNOWN')
    return dict(unknown,actions=cfg.get('actions',[]),housing_match=round(match_score,3),reason='人工标定灯体外壳不再匹配，禁止把霓虹/其他彩灯当交通灯')
   x0+=point[0];y0+=point[1];x1=x0+tw;y1=y0+th;crop=image[y0:y1,x0:x1]
  hsv=cv2.cvtColor(crop,cv2.COLOR_BGR2HSV);candidates=[]
  for state,ranges in [('RED',[(0,13),(167,179)]),('GREEN',[(38,98)])]:
   mask=np.zeros(hsv.shape[:2],np.uint8)
   for lo,hi in ranges:mask|=cv2.inRange(hsv,(lo,95,175),(hi,255,255))
   for contour in cv2.findContours(mask,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)[0]:
    x,y,bw,bh=cv2.boundingRect(contour);area=cv2.contourArea(contour)
    # Work on native pixels so distant lamps do not disappear during global resizing.
    fill=area/(bw*bh);hull_fill=cv2.contourArea(cv2.convexHull(contour))/(bw*bh)
    # A saturated white lamp core leaves a coloured crescent/ring in native H264.
    # Accept that shape only inside a matched physical housing, never bare neon.
    colour_fraction=float(np.count_nonzero(mask[y:y+bh,x:x+bw]))/(bw*bh)
    compact=fill>.28 or (self.template is not None and hull_fill>.45 and colour_fraction>.12)
    if not(4<=area<=w*h*.0006 and .5<bw/max(1,bh)<1.8 and compact and 3<=bh<=h*.04):continue
    radius=max(bw,bh);cx=x+bw//2;cy=y+bh//2
    a,b=max(0,cx-radius),min(crop.shape[1],cx+3*radius)
    c,d=max(0,cy-radius),min(crop.shape[0],cy+radius+1)
    local=hsv[c:d,a:b,2]
    # Horizontal/vertical lamp housings supported; daylight/night local exposure differs.
    dark_ratio=float(np.mean(local<110)) if local.size else 0
    if dark_ratio<.32:continue
    candidates.append(dict(state=state,box=[int(x+x0),int(y+y0),int(bw),int(bh)],area=round(area,1),dark_ratio=round(dark_ratio,3)))
  states={x['state'] for x in candidates};raw=next(iter(states)) if len(states)==1 else 'UNKNOWN'
  stable=self.stable('signal',raw)
  return dict(state=stable,raw_state=raw,confidence=.83 if stable!='UNKNOWN' else 0,actions=cfg.get('actions',[]),
   candidates=candidates,calibration=cfg,housing_match=round(match_score,3) if match_score is not None else None,roi_pixels=[int(x0),int(y0),int(x1),int(y1)],
   reason='灯组空间/控制方向为人工标定，灯色来自原图ROI，连续3帧确认' if stable!='UNKNOWN' else '灯色无可靠候选、冲突或尚未连续稳定3帧')
 def lanes(self,image):
  prep=time.perf_counter();h,w=image.shape[:2];im=cv2.resize(image,(720,round(h*720/w)),interpolation=cv2.INTER_LINEAR)
  hh,ww=im.shape[:2];y0,y1=(np.array(self.scene['road_y'])*hh).astype(int)
  hsv=cv2.cvtColor(im,cv2.COLOR_BGR2HSV);v=hsv[:,:,2]
  # Local bright ridge rejects large illuminated surfaces and most headlight pools.
  ridge=cv2.morphologyEx(v,cv2.MORPH_TOPHAT,np.ones((7,19),np.uint8))
  mask=(cv2.inRange(hsv,(0,0,110),(179,100,255)) | cv2.inRange(hsv,(12,65,90),(40,255,255)))
  mask &= ((ridge>16)|(v>210)).astype(np.uint8)*255
  mask[:y0]=0;mask[y1:]=0
  self.preprocess_ms=(time.perf_counter()-prep)*1000
  edges=cv2.Canny(mask,50,130)
  lines=cv2.HoughLinesP(edges,1,np.pi/360,threshold=18,minLineLength=18,maxLineGap=13)
  byside={'left':[],'right':[]};cy=(y0+y1)/2
  if lines is not None:
   for xa,ya,xb,yb in lines[:,0]:
    if abs(yb-ya)<11:continue
    a=(xb-xa)/(yb-ya);b=xa-a*ya;bottom=a*y1+b;top=a*y0+b
    vx,vy=self.scene['horizon']
    if abs(a*(vy*hh)+b-vx*ww)>ww*.12:continue
    # Ego boundary: points diverge from the horizon and straddle the image center.
    side='left' if a<-.18 else 'right' if a>.18 else None
    if side=='left' and not(.06*ww<bottom<.53*ww and .2*ww<top<.61*ww):continue
    if side=='right' and not(.47*ww<bottom<.96*ww and .35*ww<top<.82*ww):continue
    if side:byside[side].append((a,b,float(np.hypot(xb-xa,yb-ya)),bottom))
  output={}
  for side,ls in byside.items():
   raw='UNKNOWN';confidence=0.;coverage=0.;trace=[];segments=[];gaps=[];neighbor=False;neighbor_manual=bool(self.scene.get('adjacent_lane_manual',{}).get(side));reason='未找到稳定的当前车道边界'
   if ls:
    # Nearest painted boundary on each side, rather than far neighboring lanes.
    ls.sort(key=lambda x:abs(x[3]-ww*.5));seed=ls[0]
    group=[l for l in ls if abs(l[3]-seed[3])<ww*.045 and abs(l[0]-seed[0])<.24]
    # A dashed curb/shoulder marking alone does not prove another driving lane.
    # Look for a further geometrically consistent painted boundary outside it.
    neighbor=any((l[3]>seed[3]+ww*.12 if side=='right' else l[3]<seed[3]-ww*.12) for l in ls)
    weights=np.array([x[2] for x in group]);a=float(np.average([x[0] for x in group],weights=weights));b=float(np.average([x[1] for x in group],weights=weights))
    yy=np.arange(y0,y1);xx=a*yy+b
    occ=np.array([np.count_nonzero(mask[y,max(0,int(x)-4):min(ww,int(x)+5)])>=2 for x,y in zip(xx,yy)])
    occ=cv2.morphologyEx(occ.astype(np.uint8).reshape(-1,1),cv2.MORPH_CLOSE,np.ones((4,1),np.uint8)).ravel()>0
    segments=[(int(a),int(b)) for a,b in runs(occ) if b-a>=5]
    gaps=[(int(a),int(b)) for a,b in runs(~occ) if b-a>=6 and a>4 and b<len(occ)-4]
    coverage=float(np.mean(occ));trace=[[float(x/ww*w),float(y/hh*h)] for x,y in zip(xx[::4],yy[::4])]
    if coverage>.86 and len(gaps)==0 and len(group)>=2:raw='SOLID';confidence=.82
    elif .22<coverage<.80 and len(segments)>=3 and len(gaps)>=2 and len(group)>=2:raw='DASHED';confidence=.77
    reason='连续覆盖充分' if raw=='SOLID' else '沿线存在至少3段漆线和2段内部空隙' if raw=='DASHED' else '边界遮挡/线段数量或覆盖率不足，不能判断实虚'
   if trace:
    ends=np.array([trace[0][0]/w,trace[-1][0]/w])
    if side in self.geometry and np.max(np.abs(ends-self.geometry[side]))>.06:self.votes[side].clear()
    self.geometry[side]=ends
   state=self.stable(side,raw)
   output[side]=dict(state=state,raw_state=raw,confidence=confidence if state!='UNKNOWN' else 0,adjacent_lane_confirmed=neighbor or neighbor_manual,adjacent_lane_source='MANUAL_SCENE_CALIBRATION' if neighbor_manual else 'OUTER_MARKING' if neighbor else 'UNCONFIRMED',coverage=round(coverage,3),segments=len(segments),gaps=len(gaps),trace=trace,reason=reason if state!='UNKNOWN' or raw=='UNKNOWN' else '同一边界近5帧尚无3次一致线型证据')
  # A candidate pair must enclose the ego center; severe width inconsistency is unknown.
  if output['left']['trace'] and output['right']['trace']:
   left=output['left']['trace'];right=output['right']['trace']
   if right[-1][0]-left[-1][0]<w*.12:
    for o in output.values():o.update(state='UNKNOWN',confidence=0,reason='左右边界宽度不合理，车道归属不明确')
  return output
 def analyze(self,image):
  start=time.perf_counter();signal=self.signal(image);signal_ms=(time.perf_counter()-start)*1000
  t=time.perf_counter();lanes=self.lanes(image);lane_ms=(time.perf_counter()-t)*1000
  return dict(signal=signal,lanes=lanes,stage_ms=dict(preprocess=round(self.preprocess_ms,3),signal_roi=round(signal_ms,3),lanes=round(lane_ms-self.preprocess_ms,3),inference=round((time.perf_counter()-start)*1000-self.preprocess_ms,3)),execution='CPU OpenCV; no pretrained model',evidence_kind='REAL_IMAGE_WITH_EXPLICIT_SPATIAL_CALIBRATION')
