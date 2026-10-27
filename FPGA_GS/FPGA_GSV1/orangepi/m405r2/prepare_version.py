"""Build the independent r2 sources from preserved r1. Local one-off helper."""
from pathlib import Path
base=Path(__file__).parent
def edit(name,pairs):
 p=base/name;s=p.read_text(encoding='utf-8')
 for old,new in pairs:
  assert old in s,(name,old)
  s=s.replace(old,new)
 p.write_text(s,encoding='utf-8')
edit('road.py',[
 ("import cv2,numpy as np","import cv2,numpy as np\nfrom lane_semantics import LaneSemantics"),
 ("Path(__file__).parent/'yolop320", "Path(__file__).parent.parent/'m405'/'yolop320"),
 ("self.error=None", "self.error=None;self.semantic=LaneSemantics()"),
 ("im,epoch,frame,decoded=self.pending", "im,epoch,frame,decoded,boxes=self.pending"),
 ("result,_=model.infer(im);now=time.monotonic()", "result,masks=model.infer(im);now=time.monotonic()\n    if getattr(self,'semantic_epoch',None)!=epoch:self.semantic.reset();self.semantic_epoch=epoch\n    self.semantic.analyze(im,result,masks,boxes,now)"),
 ("def update(self,image,epoch,frame,decoded):", "def update(self,image,epoch,frame,decoded,boxes=None):"),
 ("self.pending=(image,epoch,frame,decoded)", "self.pending=(image,epoch,frame,decoded,copy.deepcopy(boxes or []))"),
 ("target_fps=8,input_size", "target_fps=8,semantic_update_fps=round((len(ts)-1)/max(.001,now-ts[0]),2) if len(ts)>1 else 0,semantic_target_fps=8,input_size"),
 ])
edit('demo.py',[
 ("VERSION='M4-05-r1'","VERSION='M4-05-r2'"),
 ("ROOT/'m405/evidence/runtime'","ROOT/'m405r2/evidence/runtime'"),
 ("ROOT/'m405/index.html'","ROOT/'m405r2/index.html'"),
 ("self.road.update(image,epoch,cursor,decoded)","self.road.update(image,epoch,cursor,decoded,obs['detection'].get('objects'))"),
 ("rd['ego'].update(state='UNKNOWN',reason='暂停或道路证据超过500ms失效')", "rd['ego'].update(state='UNKNOWN',reason='暂停或道路证据超过500ms失效');rd['lane_semantics']=dict(left=dict(state='UNKNOWN',reason='车道语义已过期',adjacent=dict(state='UNKNOWN')),right=dict(state='UNKNOWN',reason='车道语义已过期',adjacent=dict(state='UNKNOWN')),reason='超过500ms失效')"),
 ("obs['road']=self.road.update(image,epoch,cursor,decoded,obs['detection'].get('objects'))", "obs['road']=self.road.update(image,epoch,cursor,decoded,obs['detection'].get('objects'))\n    obs['legacy_lanes']=obs['lanes'];obs['lanes']=obs['road'].get('lane_semantics',{} )"),
 ("left=o['lanes']['left']['state'],right=o['lanes']['right']['state']", "left=o.get('lanes',{}).get('left',{}).get('state','UNKNOWN'),right=o.get('lanes',{}).get('right',{}).get('state','UNKNOWN')"),
 ])
edit('demo_ops.py',[
 ("m405/demo.py","m405r2/demo.py"),("M4-05-r1","M4-05-r2"),("m405/state","m405r2/state")])
edit('overlay.py',[
 ("lane=obs['lanes'][side];trace=np.array(lane['trace'])", "lane=obs.get('legacy_lanes',{}).get(side,dict(trace=[],state='UNKNOWN'));trace=np.array(lane['trace'])"),
 ("'本车道 '+('自动边界'", "'本车道 '+('原图复查'"),
 ])
