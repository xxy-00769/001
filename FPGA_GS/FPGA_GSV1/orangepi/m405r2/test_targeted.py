"""Synthetic perception/driver safeguards only; never visual accuracy evidence."""
import copy,json,time
from pathlib import Path
import numpy as np,cv2
from lane_semantics import LaneSemantics
from driving import Driving
rows=[]
sem=LaneSemantics();h,w=540,960
curve=dict(fit=[0.,0.,.5],ymin=.5,ymax=.84)
paint=np.zeros((180,320),np.uint8);paint[80:160,157:163]=255
solid=np.full((h,w),80,np.uint8);solid[250:470,477:483]=220
contrast=lambda g:cv2.morphologyEx(g,cv2.MORPH_TOPHAT,cv2.getStructuringElement(cv2.MORPH_RECT,(41,1)))
def ev(g,oc=None):return sem.evidence(curve,g,contrast(g),paint,np.zeros_like(g) if oc is None else oc)
assert ev(solid)['raw_state']=='SOLID';rows.append('continuous_paint_solid')
dash=solid.copy()
for a in range(250,470,40):dash[a+18:a+40,460:500]=80
assert ev(dash)['raw_state']=='DASHED';rows.append('repeated_visible_asphalt_gaps_dashed')
oc=np.zeros_like(dash);oc[300:365,460:500]=255
assert ev(dash,oc)['raw_state']!='DASHED';rows.append('occlusion_is_not_dashed_evidence')
blank=np.full_like(dash,80);assert ev(blank) is None;rows.append('model_paint_without_RGB_not_confirmed')
# The same strong dashed segmentation under a deep, abrupt shadow must not
# become an allowed crossing. UNKNOWN is valid; a shadow is not a clear gap.
shadow=dash.copy();shadow[292:355]=15
assert ev(shadow)['raw_state']!='DASHED';rows.append('deep_shadow_not_dashed_evidence')
d=Driving();now=time.monotonic()
def obs(kind,adj='EXISTS',fresh=True):return dict(road=dict(decoded_monotonic=now if fresh else now-1,ego=dict(state='DETECTED'),lane_semantics=dict(left=dict(state=kind,reason='fixture',adjacent=dict(state=adj)),right=dict(state=kind,adjacent=dict(state=adj)))))
d.command(dict(intent='left'),now);x=d.update(obs('SOLID'),0,now);assert x['motion']=='STRAIGHT' and x['suggestion']=='KEEP';rows.append('solid_no_cross')
x=d.update(obs('DASHED'),0,now);assert x['suggestion']=='REVIEW' and x['motion']=='STRAIGHT';rows.append('dashed_adjacent_not_safe_lane_change')
x=d.update(obs('DASHED','UNKNOWN'),0,now);assert x['suggestion']=='UNKNOWN';rows.append('adjacent_unknown_no_permission')
x=d.update(obs('SOLID',fresh=False),0,now);assert x['suggestion']=='UNKNOWN';rows.append('expired_road_no_crossing_advice')
d.command(dict(intent='stop',force=True),now);assert d.update(obs('DASHED'),0,now)['motion']=='STOPPED';rows.append('stop_priority')
sem.history['left'].append((now,'SOLID'));sem.previous={'x':1};sem.reset();assert not sem.history['left'] and sem.previous is None;rows.append('temporal_state_reset')
p=Path(__file__).parent/'evidence/targeted_tests.json';p.write_text(json.dumps(dict(scope='synthetic safeguards, not visual accuracy',passed=rows),ensure_ascii=False,indent=2));print(rows)
