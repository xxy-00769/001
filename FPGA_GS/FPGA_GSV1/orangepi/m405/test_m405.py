"""Focused M405 safety/geometry checks. Synthetic masks are NOT visual accuracy evidence."""
import threading,time,collections
import numpy as np,cv2
from road import boundaries,AsyncRoad
checks=[]
blank=np.zeros((180,320),np.uint8);full=np.full_like(blank,255)
assert boundaries(blank,full)['state']=='UNKNOWN';checks.append('no paint -> unknown')
lane=blank.copy();ys=np.linspace(.49,.94,80);left=.49-.65*(ys-.49)-.08*(ys-.49)**2;right=.51+.65*(ys-.49)+.08*(ys-.49)**2
for xs in (left,right):cv2.polylines(lane,[(np.c_[xs,ys]*[320,180]).astype('int32')],False,255,2)
g=boundaries(lane,full);assert g['state']=='DETECTED',g['reason'];checks.append('perspective-convergent mildly curved boundaries -> ego area')
for xs in (right,):cv2.polylines(lane,[(np.c_[xs,ys]*[320,180]).astype('int32')],False,0,6)
assert boundaries(lane,full)['state']=='UNKNOWN';checks.append('one boundary missing -> no completed ego area')
a=AsyncRoad.__new__(AsyncRoad);a.cv=threading.Condition();a.epoch=1;a.pending=None;a.result=dict(epoch=1,decoded_monotonic=time.monotonic()-.6,source_frame_id=10,ego=g);a.error=None;a.replaced=0;a.stamps=collections.deque()
assert a.update(np.zeros((4,4,3),np.uint8),1,15,time.monotonic())['state']=='UNKNOWN';checks.append('older than 500ms expires')
a.reset(2);assert a.result is None and a.pending is None;a.result=dict(epoch=1,decoded_monotonic=time.monotonic(),source_frame_id=10,ego=g)
assert a.update(np.zeros((4,4,3),np.uint8),3,0,time.monotonic())['state']=='UNKNOWN';checks.append('seek/video/loop epoch cannot reuse old result')
import json
print(json.dumps(dict(passed=checks,scope='geometry/state only; not accuracy'),ensure_ascii=False))
