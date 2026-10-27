from pathlib import Path
import hashlib,json,ast
p=Path('orangepi/m404');repo=json.loads((p/'model_repo.json').read_text(encoding='utf-8'))
classes=None
for node in ast.parse((p/'models/reference_yolov8.py').read_text(encoding='utf-8')).body:
 if isinstance(node,ast.Assign) and any(isinstance(x,ast.Name) and x.id=='CLASSES' for x in node.targets):classes=list(ast.literal_eval(node.value))
classes=[x.strip() for x in classes];classes[3]='motorcycle'
art=[]
for name in ['yolov8n.rknn','yolov8n.onnx','rknn_lite.whl','ruamel_yaml.whl','onnxruntime.whl']:
 f=p/'models'/name;art.append(dict(name=name,remote_path=name,bytes=f.stat().st_size,sha256=hashlib.sha256(f.read_bytes()).hexdigest()))
m=dict(release='M4-04-r1',model='YOLOv8n COCO',input=[1,640,640,3],input_format='NHWC RGB uint8, letterbox fill114; RKNN normalization embedded. ONNX NCHW RGB float32/255.',deployment='RK3588S RKNN/NPU, cores0+1+2',rknn_model_repository=repo['id'],revision=repo['sha'],publisher_release='v2.4.0',embedded_compiler='2.3.3b3 (b190a7fa82@2025-07-24T11:55:41)',actual_runtime='system librknnrt 2.3.0 (c949ad889d), driver0.9.8; verified on real frames',python_api='rknn-toolkit-lite2 2.5.0, isolated .venv404',python_api_source='https://github.com/airockchip/rknn-toolkit2/tree/2c723177a94fac65cbc036d722907ddbc91980cf',model_license='AGPL-3.0; models/LICENSE.yolov8.txt',postprocess_reference='airockchip/rknn_model_zoo examples/yolov8, Apache-2.0',onnx_source='https://ftrg.zbox.filez.com/v2/delivery/data/95f00b0fc900458ba134f8b180b3f7a1/examples/yolov8/yolov8n.onnx',classes=classes,displayed_coco_ids={0:'行人',1:'自行车',2:'汽车',3:'摩托车',5:'客车',7:'货车'},unsupported=['电动车细分','锥桶','施工围栏','通用障碍物'],confidence_threshold=.25,nms_iou=.45,quantization='INT8 w8a8, publisher supplied; not retrained',artifacts=art,dependency_notes=['Inherited system OpenCV4.5.4/NumPy1.21.5/Pillow9.0.1/psutil5.9.0','ruamel.yaml0.18.6 isolated wheel','onnxruntime1.20.1 CPU only for same-frame deployment comparison','Downloaded librknnrt2.5.0 is NOT loaded/installed; system library remains unchanged.'])
(p/'model_manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
rows=json.loads((p/'evidence/model_comparison.json').read_text(encoding='utf-8'));summary=[]
for row in rows:
 matches=[x for x in row['matches'] if x['iou']>=.5]
 summary.append(dict(video=row['video'],seconds=row['seconds'],onnx_count=len(row['onnx_objects']),npu_count=row['rknn']['detected_count'],same_class_iou_over_05=len(matches),mean_iou=sum(x['iou'] for x in matches)/len(matches) if matches else None,onnx_cpu_ms=row['onnx_ms']))
(p/'evidence/comparison_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
