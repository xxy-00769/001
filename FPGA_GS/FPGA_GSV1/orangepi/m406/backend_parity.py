"""Same real input, ONNX CPU vs FP16 RKNN. Deployment parity, not accuracy."""
import cv2,numpy as np,onnxruntime as ort,json,sys
from pathlib import Path
from rknnlite.api import RKNNLite
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'m404'))
from detector import prepare
cv2.setNumThreads(2);ss=ort.SessionOptions();ss.intra_op_num_threads=2;ss.inter_op_num_threads=1
s=ort.InferenceSession(str(ROOT/'m406/yolov8s640.onnx'),ss,providers=['CPUExecutionProvider']);r=RKNNLite();r.load_rknn(str(ROOT/'m406/yolov8s640_fp16.rknn'));r.init_runtime(core_mask=RKNNLite.NPU_CORE_2)
rows=[]
for name in ['SC_BT_8','SC_BT_55','SC_YJ_99','SC_YJ_105','SC_YJ2_20','SC_BT2_15']:
 im=cv2.imread(str(ROOT/'m406/evidence/proposals'/(name+'_raw.jpg')));h,w=im.shape[:2];a,_=prepare(im[int(.12*h):int(.66*h),:int(.55*w)]);cpu=s.run(None,{'images':a.transpose(0,3,1,2).astype(np.float32)/255})[0];npu=r.inference(inputs=[a])[0]
 c=cpu[0];n=npu[0];ids=np.where(c[9+4]>.25)[0]
 rows.append(dict(name=name,max_traffic_score_cpu=float(c[13].max()),max_traffic_score_npu=float(n[13].max()),traffic_score_max_abs_error=float(np.abs(c[13]-n[13]).max()),traffic_candidates_cpu=int((c[13]>.25).sum()),traffic_candidates_npu=int((n[13]>.25).sum()),candidate_xywh_mean_abs_error_pixels=float(np.abs(c[:4,ids]-n[:4,ids]).mean())if len(ids)else None))
r.release();(ROOT/'m406/evidence/backend_parity.json').write_text(json.dumps(rows,indent=2));print(json.dumps(rows,indent=2))
