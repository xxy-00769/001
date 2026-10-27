import json,time
from pathlib import Path
import cv2,numpy as np,onnxruntime as ort
from detector import Detector,prepare,postprocess
root=Path(__file__).resolve().parent
opts=ort.SessionOptions();opts.intra_op_num_threads=2;opts.inter_op_num_threads=1
session=ort.InferenceSession(str(root/'yolov8n.onnx'),sess_options=opts,providers=['CPUExecutionProvider']);det=Detector();rows=[]
for name in json.loads((root/'failures_to_compare.json').read_text()):
 p=root/'evidence/runtime'/name;raw=cv2.imread(str(p)+'_raw.jpg');assert raw is not None
 saved=json.loads(p.with_suffix('.json').read_text()) if p.with_suffix('.json').exists() else json.loads(Path(str(p)+'.json').read_text())
 x,tr=prepare(raw);outputs=session.run(None,{session.get_inputs()[0].name:x.transpose(0,3,1,2).astype(np.float32)/255})
 row=dict(snapshot=name,video=saved['video'],position=saved['position'],cpu=postprocess(outputs,tr,raw.shape),npu=det.detect(raw,0,saved['frame_id']))
 rows.append(row);print(name,[(d['label'],d['confidence'],d['box']) for d in row['cpu']],flush=True)
(root/'evidence/failure_comparison.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2));det.close()
