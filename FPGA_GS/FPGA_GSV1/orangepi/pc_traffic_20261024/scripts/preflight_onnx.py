import os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
os.environ['YOLO_CONFIG_DIR']=str(ROOT/'artifacts/ultralytics_settings')
os.environ['MPLCONFIGDIR']=str(ROOT/'artifacts/matplotlib_cache')
os.environ['YOLO_AUTOINSTALL']='false'
import torch,onnx,onnxruntime as ort,numpy as np,cv2,json,hashlib,collections,importlib.metadata as md
from ultralytics.nn.tasks import DetectionModel
from ultralytics.utils import ROOT as ULTRA_ROOT

torch.manual_seed(20261024);torch.set_num_threads(4)
model=DetectionModel(str(ULTRA_ROOT/'cfg/models/v8/yolov8.yaml'),ch=3,nc=2,verbose=False).eval()
model.fuse(verbose=False)
for layer in model.modules():
 if layer.__class__.__name__=='Detect':layer.export=True;layer.dynamic=False;layer.format='onnx'
path=ROOT/'artifacts/yolov8n_2class_640_UNTRAINED_preflight.onnx'
x=torch.zeros((1,3,640,640))
torch.onnx.export(model,x,str(path),opset_version=12,input_names=['images'],output_names=['predictions'],do_constant_folding=True,dynamic_axes=None)
graph=onnx.load(path);onnx.checker.check_model(graph);ops=collections.Counter(n.op_type for n in graph.graph.node)
opts=ort.SessionOptions();opts.intra_op_num_threads=4;session=ort.InferenceSession(str(path),opts,providers=['CPUExecutionProvider'])
checks=[]
for color in ['RED','GREEN']:
 im=cv2.imread(str(ROOT.parent/'m406/evidence/exact_source'/f'{color}_raw.jpg'));h,w=im.shape[:2]
 for mode in ['full','left_half']:
  a=im if mode=='full' else im[int(.12*h):int(.66*h),:int(.55*w)]
  hh,ww=a.shape[:2];s=min(640/ww,640/hh);nw,nh=round(ww*s),round(hh*s);left,top=(640-nw)//2,(640-nh)//2
  tensor=np.full((640,640,3),114,np.uint8);tensor[top:top+nh,left:left+nw]=cv2.resize(a,(nw,nh));tensor=np.ascontiguousarray(tensor[:,:,::-1].transpose(2,0,1)[None],dtype=np.float32)/255
  with torch.inference_mode():ref=model(torch.from_numpy(tensor)).numpy()
  got=session.run(None,{'images':tensor})[0];diff=np.abs(ref-got)
  checks.append({'image':color,'mode':mode,'shape':list(got.shape),'max_abs_error':float(diff.max()),'mean_abs_error':float(diff.mean()),'box_max_abs_error_input_pixels':float(diff[:,:4].max()),'score_max_abs_error':float(diff[:,4:].max())})
assert all(c['box_max_abs_error_input_pixels']<0.01 and c['score_max_abs_error']<1e-5 for c in checks),checks
result={'passed':True,'scope':'Torch CPU to ONNX CPU only; untrained architecture, no accuracy claim, no RKNN build','trained':False,'architecture':'YOLOv8n standard head nc=2','parameters':sum(p.numel() for p in model.parameters()),'opset':12,'input':[1,3,640,640],'output':[1,6,8400],'preprocessing':'RGB NCHW float32 /255; letterbox114; static640; no embedded NMS','ops':dict(ops),'onnx_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'onnx_bytes':path.stat().st_size,'comparisons':checks,'torch_cuda_available':torch.cuda.is_available(),'torch_cuda_version':torch.version.cuda,'versions':{p:md.version(p) for p in ['torch','torchvision','ultralytics','numpy','onnx','onnxruntime','opencv-python']},'rknn_conversion_passed':False}
(ROOT/'reports/onnx_preflight.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result,indent=2))
# Existing trusted project checkpoints: inspect identity only, never mutate them.
ident=[]
for p in [ROOT.parent/'m406/research/yolov8s.pt',ROOT.parent/'m406/research/tlony/tlony-yolov8n/weights/best.pt']:
 ck=torch.load(p,map_location='cpu',weights_only=False);m=ck.get('ema') or ck.get('model')
 ident.append({'path':str(p),'model_type':type(m).__name__,'names':m.names,'yaml':m.yaml,'parameters':sum(x.numel() for x in m.parameters()),'layer_types':dict(collections.Counter(type(x).__name__ for x in m.modules()))})
(ROOT/'reports/checkpoint_identity.json').write_text(json.dumps(ident,ensure_ascii=False,indent=2,default=str),encoding='utf-8')
