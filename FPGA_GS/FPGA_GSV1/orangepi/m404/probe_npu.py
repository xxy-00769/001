import os,sys,zipfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
if 'probe' not in sys.argv:
 import subprocess
 subprocess.check_call(['python3','-m','venv','--without-pip','--system-site-packages',str(root/'.venv404')])
 with zipfile.ZipFile(root/'m404/rknn_lite.whl') as z:z.extractall(root/'.venv404/lib/python3.10/site-packages')
 os.environ['LD_LIBRARY_PATH']=str(root/'m404')
 os.execv(str(root/'.venv404/bin/python'),[str(root/'.venv404/bin/python'),__file__,'probe'])
from rknnlite.api import RKNNLite
import numpy as np
r=RKNNLite(verbose=True)
assert r.load_rknn(str(root/'m404/yolov8n.rknn'))==0
assert r.init_runtime(core_mask=RKNNLite.NPU_CORE_0_1_2)==0
out=r.inference(inputs=[np.zeros((1,640,640,3),np.uint8)])
print('OUTPUTS',[(x.shape,str(x.dtype),float(x.min()),float(x.max())) for x in out])
r.release()
