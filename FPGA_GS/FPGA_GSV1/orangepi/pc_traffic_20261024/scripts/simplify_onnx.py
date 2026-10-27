from pathlib import Path
import onnx,onnxsim,json,hashlib,collections,numpy as np,onnxruntime as ort
r=Path(__file__).resolve().parents[1];p=r/'artifacts/yolov8n_2class_640_UNTRAINED_preflight.onnx';m=onnx.load(p)
s,ok=onnxsim.simplify(m);assert ok;onnx.checker.check_model(s)
p2=p.with_name(p.stem+'_simplified.onnx');onnx.save(s,p2)
o=ort.SessionOptions();o.intra_op_num_threads=4
s1=ort.InferenceSession(str(p),o,providers=['CPUExecutionProvider']);s2=ort.InferenceSession(str(p2),o,providers=['CPUExecutionProvider']);x=np.random.default_rng(0).random((1,3,640,640),dtype=np.float32)
diff=np.abs(s1.run(None,{'images':x})[0]-s2.run(None,{'images':x})[0]);assert float(diff.max())<0.01
out={'passed':True,'onnx_path':str(p2),'onnx_sha256':hashlib.sha256(p2.read_bytes()).hexdigest(),'ops':dict(collections.Counter(n.op_type for n in s.graph.node)),'original_vs_simplified_max_abs_error':float(diff.max()),'rknn_build_passed':False}
(r/'reports/onnx_simplified.json').write_text(json.dumps(out,indent=2),encoding='utf-8');print(json.dumps(out,indent=2))
