import json,sys
from pathlib import Path
import cv2
from detector import Detector
root=Path(__file__).resolve().parents[1];out=root/'m404/evidence/check';out.mkdir(parents=True,exist_ok=True)
d=Detector()
for name,sec in [('SC_BT.mp4',10),('SC_BT.mp4',32),('SC_BT2.mp4',12),('SC_YJ.mp4',30),('SC_YJ.mp4',105),('SC_YJ2.mp4',20)]:
 cap=cv2.VideoCapture(str(root/'media'/name));cap.set(cv2.CAP_PROP_POS_MSEC,sec*1000);ok,im=cap.read();cap.release();assert ok
 result=d.detect(im,0,int(sec*30));print(name,sec,result['detected_count'],[(x['label'],x['confidence']) for x in result['objects']],result['stage_ms'],flush=True)
 base=out/f'{name[:-4]}_{sec}';cv2.imwrite(str(base)+'_raw.jpg',im);base.with_suffix('.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
d.close()
