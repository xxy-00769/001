from rknn.api import RKNN
r=RKNN(verbose=False)
assert r.config(mean_values=[[0,0,0]],std_values=[[255,255,255]],target_platform='rk3588',optimization_level=3)==0
assert r.load_onnx(model='m406/tlony640.onnx')==0
assert r.build(do_quantization=False)==0
assert r.export_rknn('m406/tlony640_fp16.rknn')==0
r.release()
