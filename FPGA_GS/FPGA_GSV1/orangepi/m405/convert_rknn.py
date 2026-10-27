from rknn.api import RKNN
r=RKNN(verbose=False)
assert r.config(mean_values=[[123.675,116.28,103.53]],std_values=[[58.395,57.12,57.375]],target_platform='rk3588',optimization_level=3)==0
assert r.load_onnx(model='m405/yolop320.onnx',outputs=['drive_area_seg','lane_line_seg'])==0
assert r.build(do_quantization=False)==0
assert r.export_rknn('m405/yolop320_fp16.rknn')==0
r.release()
