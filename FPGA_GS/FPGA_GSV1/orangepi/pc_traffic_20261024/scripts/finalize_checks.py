from pathlib import Path
import json,hashlib,csv
r=Path(__file__).resolve().parents[1]
(r/'reports/rknn_preflight.json').write_text(json.dumps({'passed':False,'status':'not_run','reason':'No isolated supported Linux RKNN conversion environment in this PC task. No board services accessed.','onnx_sha256':'5cb102190d135e7019f8ced291d853121b060de5995f0943da58611ee0898201'},indent=2),encoding='utf-8')
(r/'reports/pytorch_cuda_smoke.json').write_text(json.dumps({'passed':False,'status':'not_run','reason':'CUDA wheel download was stopped; installed environment is Torch CPU for ONNX preflight. Driver memory probe passed separately.'},indent=2),encoding='utf-8')
before=json.loads((r/'reports/protected_before.json').read_text(encoding='utf-8'));changed=[];missing=[]
for row in before:
 p=r.parent/row['path']
 if not p.exists():missing.append(row['path'])
 elif hashlib.sha256(p.read_bytes()).hexdigest()!=row['sha256']:changed.append(row['path'])
out={'checked_files':len(before),'changed':changed,'missing':missing,'passed':not changed and not missing,'scope':'m404/m405/m405r2/m406/oneclick non-evidence tracked source/models selected at initial snapshot; not a global disk audit'}
(r/'reports/protected_after_check.json').write_text(json.dumps(out,indent=2),encoding='utf-8');print(json.dumps(out,indent=2))
# Review-screened metadata is not a completed annotation or independent review.
indices=[round(i*399/39) for i in range(40)];night={164,174,184,194,205,256,266,276}
(r/'reports/contact_screening.json').write_text(json.dumps({'status':'visual_screening_only_not_full_annotation','images':[{'sample_id':f's2tld1080_{i:04d}','day_night_screening':'night' if i in night else 'day','label_review':'pending','site_review':'pending'} for i in indices],'notes':['Horizontal and vertical Chinese road lights visible.','Night rain, glare, auxiliary LED text, tail lights and reflection visible.','Source labels and image-level lamp completeness have not been approved.']},indent=2),encoding='utf-8')
