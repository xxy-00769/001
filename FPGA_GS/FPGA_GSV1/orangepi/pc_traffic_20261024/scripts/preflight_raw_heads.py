"""Export only: retain standard training architecture, expose six head tensors for RKNN."""
import os,copy,types,json,hashlib,collections
from pathlib import Path
R=Path(__file__).resolve().parents[1]
os.environ['YOLO_CONFIG_DIR']=str(R/'artifacts/ultralytics_settings');os.environ['MPLCONFIGDIR']=str(R/'artifacts/matplotlib_cache');os.environ['YOLO_AUTOINSTALL']='false'
import torch,onnx,onnxsim,onnxruntime as ort,numpy as np,cv2
from onnx import helper,numpy_helper,TensorProto
from ultralytics.nn.tasks import DetectionModel
from ultralytics.utils import ROOT as UROOT

torch.manual_seed(20261024);torch.set_num_threads(4)
ref=DetectionModel(str(UROOT/'cfg/models/v8/yolov8.yaml'),ch=3,nc=2,verbose=False).eval();ref.fuse(verbose=False)
for layer in ref.modules():
 if type(layer).__name__=='Detect':layer.export=True;layer.dynamic=False;layer.format='onnx'
model=copy.deepcopy(ref)
def raw_head(self,x):
 out=[]
 for i in range(self.nl):out.extend((self.cv2[i](x[i]),self.cv3[i](x[i]).sigmoid()))
 return tuple(out)
model.model[-1].forward=types.MethodType(raw_head,model.model[-1])
p=R/'artifacts/yolov8n_2class_640_UNTRAINED_raw6.onnx';names=['box_s8','score_s8','box_s16','score_s16','box_s32','score_s32']
torch.onnx.export(model,torch.zeros(1,3,640,640),str(p),opset_version=12,input_names=['images'],output_names=names,do_constant_folding=True)
m,ok=onnxsim.simplify(onnx.load(p));assert ok
init={i.name:numpy_helper.to_array(i) for i in m.graph.initializer};changes=[]
for n in m.graph.node:
 if n.op_type!='Resize':continue
 attrs={a.name:helper.get_attribute_value(a) for a in n.attribute}
 assert attrs['mode']==b'nearest' and attrs['coordinate_transformation_mode']==b'asymmetric' and attrs['nearest_mode']==b'floor',attrs
 assert np.array_equal(init[n.input[2]],np.array([1,1,2,2])),n.name
 # For exactly 2x upsampling, asymmetric+floor and half_pixel+round_prefer_floor
 # both select floor(destination_index/2). Do not apply this rewrite to other scales.
 del n.attribute[:]
 n.attribute.extend([helper.make_attribute('mode','nearest'),helper.make_attribute('coordinate_transformation_mode','half_pixel')])
 changes.append({'node':n.name,'old':{k:str(v) for k,v in attrs.items()},'new':{'mode':'nearest','coordinate_transformation_mode':'half_pixel','nearest_mode':'round_prefer_floor(default)'},'scale':[1,1,2,2]})
assert len(changes)==2
p2=R/'artifacts/yolov8n_2class_640_UNTRAINED_raw6_rknn_preflight.onnx';onnx.checker.check_model(m);onnx.save(m,p2)
opt=ort.SessionOptions();opt.intra_op_num_threads=4
# Isolated Resize checks use nonconstant ramps + random signals so an untrained head
# cannot conceal a spatial indexing error.
def resize_session(shape,mode,nearest):
 node=helper.make_node('Resize',['X','roi','scales'],['Y'],mode='nearest',coordinate_transformation_mode=mode,nearest_mode=nearest)
 g=helper.make_graph([node],'resize',[helper.make_tensor_value_info('X',TensorProto.FLOAT,shape)],[helper.make_tensor_value_info('Y',TensorProto.FLOAT,[shape[0],shape[1],shape[2]*2,shape[3]*2])],[numpy_helper.from_array(np.array([],np.float32),'roi'),numpy_helper.from_array(np.array([1,1,2,2],np.float32),'scales')])
 test=helper.make_model(g,opset_imports=[helper.make_opsetid('',12)]);test.ir_version=9
 return ort.InferenceSession(test.SerializeToString(),opt,providers=['CPUExecutionProvider'])
resize_checks=[]
for shape in [(1,1,1,1),(1,2,3,5),(1,3,20,20),(1,2,40,40)]:
 a=np.arange(np.prod(shape),dtype=np.float32).reshape(shape);a+=np.random.default_rng(7).random(shape,dtype=np.float32)
 x=resize_session(shape,'asymmetric','floor').run(None,{'X':a})[0];y=resize_session(shape,'half_pixel','round_prefer_floor').run(None,{'X':a})[0]
 assert np.array_equal(x,y);resize_checks.append({'input':list(shape),'exact_equal':True})
session=ort.InferenceSession(str(p2),opt,providers=['CPUExecutionProvider'])
def decode(outputs):
 result=[]
 for i,stride in enumerate([8,16,32]):
  box,score=outputs[2*i:2*i+2];_,_,h,w=box.shape
  a=box.reshape(1,4,16,h,w);a=np.exp(a-a.max(axis=2,keepdims=True));a/=a.sum(axis=2,keepdims=True)
  dist=(a*np.arange(16,dtype=np.float32).reshape(1,1,16,1,1)).sum(axis=2)
  yy,xx=np.mgrid[:h,:w];gx=xx.astype(np.float32)+.5;gy=yy.astype(np.float32)+.5
  x1=gx-dist[:,0];y1=gy-dist[:,1];x2=gx+dist[:,2];y2=gy+dist[:,3]
  xywh=np.stack(((x1+x2)/2,(y1+y2)/2,x2-x1,y2-y1),axis=1)*stride
  result.append(np.concatenate((xywh.reshape(1,4,-1),score.reshape(1,2,-1)),axis=1))
 return np.concatenate(result,axis=2)
checks=[]
for color in ['RED','GREEN']:
 im=cv2.imread(str(R.parent/'m406/evidence/exact_source'/f'{color}_raw.jpg'));h,w=im.shape[:2]
 for mode in ['full','left_half']:
  a=im if mode=='full' else im[int(.12*h):int(.66*h),:int(.55*w)]
  hh,ww=a.shape[:2];s=min(640/ww,640/hh);nw,nh=round(ww*s),round(hh*s);l,t=(640-nw)//2,(640-nh)//2
  rgb=np.full((640,640,3),114,np.uint8);rgb[t:t+nh,l:l+nw]=cv2.resize(a,(nw,nh));inp=np.ascontiguousarray(rgb[:,:,::-1].transpose(2,0,1)[None],dtype=np.float32)/255
  with torch.inference_mode():want=ref(torch.from_numpy(inp)).numpy();raw_ref=[v.numpy() for v in model(torch.from_numpy(inp))]
  raw=session.run(None,{'images':inp});got=decode(raw)
  check={'image':color,'mode':mode,'raw_max_abs_error':max(float(np.abs(a-b).max()) for a,b in zip(raw_ref,raw)),'decoded_box_max_abs_error_input_pixels':float(np.abs(want[:,:4]-got[:,:4]).max()),'decoded_score_max_abs_error':float(np.abs(want[:,4:]-got[:,4:]).max())}
  assert check['raw_max_abs_error']<1e-4 and check['decoded_box_max_abs_error_input_pixels']<.01 and check['decoded_score_max_abs_error']<1e-5,check
  checks.append(check)
# Export per-node shapes and attributes for SDK constraint review.
shaped=onnx.shape_inference.infer_shapes(m);shapes={v.name:[d.dim_value for d in v.type.tensor_type.shape.dim] for v in list(shaped.graph.value_info)+list(shaped.graph.input)+list(shaped.graph.output)}
nodes=[{'name':n.name,'op':n.op_type,'input_shapes':[shapes.get(x) for x in n.input],'output_shapes':[shapes.get(x) for x in n.output],'attributes':{a.name:str(helper.get_attribute_value(a)) for a in n.attribute}} for n in m.graph.node]
(R/'reports/deployment_nodes.json').write_text(json.dumps(nodes,indent=2),encoding='utf-8')
out={'passed':True,'trained':False,'scope':'Torch/ONNX CPU only. RKNN Linux build and board NPU are still pending.','onnx_path':str(p2),'onnx_sha256':hashlib.sha256(p2.read_bytes()).hexdigest(),'opset':12,'ops':dict(collections.Counter(n.op_type for n in m.graph.node)),'outputs':[{'name':x.name,'shape':x.shape} for x in session.get_outputs()],'resize_changes':changes,'resize_equivalence_checks':resize_checks,'comparisons':checks,'postprocessing':'CPU DFL decode with reg_max16, strides8/16/32, sigmoid scores already applied, then class-aware NMS; do not apply a second sigmoid','sdk_document_revision':'2c723177a94fac65cbc036d722907ddbc91980cf','rknn_build_passed':False}
(R/'reports/deployment_preflight.json').write_text(json.dumps(out,indent=2),encoding='utf-8');print(json.dumps(out,indent=2))
