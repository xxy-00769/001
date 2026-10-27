"""Same native frames, identical RGB letterbox/DFL/NMS, float ONNX vs RKNN."""
import json,time,hashlib
from pathlib import Path
import cv2,numpy as np,onnxruntime as ort
from detector import Detector,prepare,postprocess,iou
root=Path(__file__).resolve().parents[1];out=root/'m404/evidence/comparison';out.mkdir(parents=True,exist_ok=True)
opts=ort.SessionOptions();opts.intra_op_num_threads=2;opts.inter_op_num_threads=1
session=ort.InferenceSession(str(root/'m404/yolov8n.onnx'),sess_options=opts,providers=['CPUExecutionProvider'])
print('ONNX',[(x.name,x.shape) for x in session.get_inputs()],[(x.name,x.shape) for x in session.get_outputs()],flush=True)
det=Detector();rows=[]
for name,sec in [('SC_BT.mp4',.5),('SC_BT.mp4',57),('SC_BT2.mp4',12),('SC_YJ.mp4',20),('SC_YJ.mp4',105),('SC_YJ2.mp4',20)]:
 cap=cv2.VideoCapture(str(root/'media'/name));cap.set(cv2.CAP_PROP_POS_MSEC,sec*1000);ok,image=cap.read();cap.release();assert ok
 tensor,tr=prepare(image);x=tensor.transpose(0,3,1,2).astype(np.float32)/255
 t=time.perf_counter();outputs=session.run(None,{session.get_inputs()[0].name:x});elapsed=(time.perf_counter()-t)*1000
 identity='decoded-sha256:'+hashlib.sha256(image.tobytes()).hexdigest()
 cpu=postprocess(outputs,tr,image.shape);npu=det.detect(image,0,identity);matches=[]
 for a in cpu:
  options=[(iou(a['box'],b['box']),b) for b in npu['objects'] if b['class_id']==a['class_id']]
  best=max(options,key=lambda x:x[0],default=(0,None));matches.append(dict(cpu=a,npu=best[1],iou=best[0]))
 row=dict(video=name,seconds=sec,time_note='OpenCV nominal seek; VFR comparison time is not exact native PTS. Both models use the identical decoded array.',image_identity=identity,shape=list(image.shape),onnx_objects=cpu,rknn=npu,matches=matches,onnx_ms=elapsed)
 rows.append(row);base=out/f'{name[:-4]}_{sec}';cv2.imwrite(str(base)+'_raw.jpg',image);Path(str(base)+'.json').write_text(json.dumps(row,ensure_ascii=False,indent=2))
 print(name,sec,'CPU',[(d['category'],d['confidence']) for d in cpu],'NPU',[(d['category'],d['confidence']) for d in npu['objects']],flush=True)
(out/'summary.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2));det.close()
