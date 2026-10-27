import zipfile,sys,json
from pathlib import Path
base=Path(__file__).resolve().parent
vendor=base/'build_vendor';vendor.mkdir(exist_ok=True)
for p in base.glob('*.whl'):zipfile.ZipFile(p).extractall(vendor)
# Export-only: do not import training/cloud/plotting frontends. Forward layers,
# weights and Detect math remain original Ultralytics 8.3.40 source.
(vendor/'ultralytics/__init__.py').write_text("__version__ = '8.3.40'\n")
for p in (vendor/'ultralytics').rglob('*.py'):
 text=p.read_text()
 text=text.replace('import matplotlib.pyplot as plt','plt = None  # export-only, plotting disabled')
 text=text.replace('importlib.metadata.version("torchvision")',"'0.17.0'  # metadata only; torchvision not used by forward")
 p.write_text(text)
import types
try:import requests
except ImportError:sys.modules['requests']=types.ModuleType('requests')
sys.path.insert(0,str(vendor))
import torch
torch.set_num_threads(2)
ckpt=torch.load(base/'tlony.pt',map_location='cpu',weights_only=False)
print('checkpoint',ckpt.keys(),'ema',type(ckpt.get('ema')),flush=True)
model=(ckpt.get('ema') or ckpt['model']).float().eval()
print(type(model),model.names,flush=True)
print('training metadata',ckpt.get('epoch'),ckpt.get('train_metrics'),flush=True)
import cv2,numpy as np
im=cv2.imread(str(base/'evidence/proposals/SC_YJ_99_raw.jpg'))
for size in (640,1280):
 h,w=im.shape[:2];scale=min(size/w,size/h);nw,nh=round(w*scale),round(h*scale);a=np.full((size,size,3),114,np.uint8);a[(size-nh)//2:(size-nh)//2+nh,(size-nw)//2:(size-nw)//2+nw]=cv2.resize(im,(nw,nh))
 with torch.no_grad():y=model(torch.from_numpy(a[:,:,::-1].copy().transpose(2,0,1)[None]).float()/255)[0]
 print('torch native',size,y.shape,float(y[:,4:].max()),flush=True)
(base/'classes.json').write_text(json.dumps(model.names,indent=2))
model.fuse()
for m in model.modules():
 if m.__class__.__name__=='Detect':m.export=True;m.dynamic=False;m.format='onnx'
torch.onnx.export(model,torch.zeros(1,3,640,640),str(base/'tlony640.onnx'),opset_version=12,input_names=['images'],output_names=['predictions'],do_constant_folding=True)
print('ONNX ready',flush=True)
