import sys,types,torch
from pathlib import Path
base=Path(__file__).resolve().parent;sys.path.insert(0,str(base/'build_vendor'));sys.modules['requests']=types.ModuleType('requests')
torch.set_num_threads(2);ck=torch.load(base/'yolov8s.pt',map_location='cpu',weights_only=False);model=ck['model'].float().eval();model.fuse()
for m in model.modules():
 if m.__class__.__name__=='Detect':m.export=True;m.dynamic=False;m.format='onnx'
torch.onnx.export(model,torch.zeros(1,3,640,640),str(base/'yolov8s640.onnx'),opset_version=12,input_names=['images'],output_names=['predictions'],do_constant_folding=True)
from rknn.api import RKNN
r=RKNN(verbose=False);assert r.config(mean_values=[[0,0,0]],std_values=[[255,255,255]],target_platform='rk3588',optimization_level=3)==0
assert r.load_onnx(model=str(base/'yolov8s640.onnx'))==0;assert r.build(do_quantization=False)==0;assert r.export_rknn(str(base/'yolov8s640_fp16.rknn'))==0;r.release()
