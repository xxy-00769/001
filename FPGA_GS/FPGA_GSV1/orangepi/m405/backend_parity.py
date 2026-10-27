import sys,json,bisect,time,hashlib
from pathlib import Path
import cv2,numpy as np
from road import RoadModel
cpu=RoadModel('onnx');npu=RoadModel();rows=[]
for video,sec in [('SC_BT.mp4',32),('SC_BT2.mp4',12),('SC_YJ.mp4',18),('SC_YJ2.mp4',20)]:
 pts=json.loads((Path('m403')/(video+'.pts.json')).read_text());idx=bisect.bisect_right(pts,sec)-1;c=cv2.VideoCapture('media/'+video)
 if video=='SC_YJ2.mp4':
  for _ in range(idx):c.grab()
 else:c.set(cv2.CAP_PROP_POS_FRAMES,idx)
 ok,im=c.read();assert ok;c.release();a,am=cpu.infer(im);b,bm=npu.infer(im)
 row=dict(video=video,source_frame_id=idx,pts=pts[idx],image_sha256=hashlib.sha256(im.tobytes()).hexdigest(),onnx_stage=a['stage_ms'],rknn_stage=b['stage_ms'],pixel_agreement=[round(float(np.mean(x==y)),6) for x,y in zip(am,bm)],ego_cpu=a['ego']['state'],ego_npu=b['ego']['state'])
 rows.append(row);print(json.dumps(row),flush=True)
Path('m405/evidence/backend_parity.json').write_text(json.dumps(rows,indent=2));npu.close()
