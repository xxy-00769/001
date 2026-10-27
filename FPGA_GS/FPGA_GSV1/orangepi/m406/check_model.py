import sys,json,cv2,numpy as np
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'m404'))
from detector import prepare
import onnxruntime as ort
from rknnlite.api import RKNNLite
ss=ort.SessionOptions();ss.intra_op_num_threads=2;s=ort.InferenceSession(str(ROOT/'m406/tlony640.onnx'),ss,providers=['CPUExecutionProvider'])
r=RKNNLite();r.load_rknn(str(ROOT/'m406/tlony640_fp16.rknn'));r.init_runtime(core_mask=RKNNLite.NPU_CORE_0)
im=cv2.imread(str(ROOT/'m406/evidence/proposals/SC_YJ_99_raw.jpg'));h,w=im.shape[:2]
for scope,box in [('full',(0,0,w,h)),('left',(0,.2*h,.55*w,.65*h)),('right',(.45*w,.2*h,w,.65*h)),('native_debug',(1450,560,1790,725))]:
 x0,y0,x1,y1=map(int,box);a,tr=prepare(im[y0:y1,x0:x1]);cpu=s.run(None,{'images':a.transpose(0,3,1,2).astype(np.float32)/255})[0];npu=r.inference(inputs=[a])[0]
 print(scope,cpu.shape,npu.shape,'max',cpu[:,4:].max(),npu[:,4:].max(),'error',np.abs(cpu-npu).mean(),flush=True)
 p=cpu[0].T;ids=np.argsort(p[:,4:].max(1))[-5:];print(p[ids],flush=True)
r.release()
