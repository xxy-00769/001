import sys,json,copy
from pathlib import Path
import cv2
from lane_semantics import LaneSemantics
root=Path(__file__).parent.parent
for name in ['SC_BT_20','SC_BT_32','SC_BT_57','SC_BT2_12','SC_YJ_20','SC_YJ_130','SC_YJ2_50']:
 p=root/'m405/evidence/audit';im=cv2.imread(str(p/(name+'_raw.jpg')))
 rd=json.loads((p/(name+'.json')).read_text())['observation']['road']
 masks=[cv2.imread(str(p/(name+'_'+k+'.png')),0) for k in ['road','paint']]
 sem=LaneSemantics();sem.analyze(im,rd,masks)
 d=rd['lane_semantics']
 print(name,rd['ego']['state'],[(s,d[s]['raw_state'],d[s]['evidence'].get('rgb_coverage'),d[s]['evidence'].get('paint_runs'),d[s]['evidence'].get('clean_gaps'),d[s]['adjacent']['state']) for s in ['left','right']],rd['stage_ms'],flush=True)
 (root/'m405r2/evidence'/f'{name}_probe.json').write_text(json.dumps(rd,ensure_ascii=False,indent=2))
