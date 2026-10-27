from pathlib import Path
import csv,json,hashlib,re
from PIL import Image
r=Path(__file__).resolve().parents[1];rows=list(csv.DictReader((r/'data/candidates.csv').open(encoding='utf-8-sig')));errors=[]
for row in rows:
 p=r/row['image_path']
 if hashlib.sha256(p.read_bytes()).hexdigest()!=row['sha256']:errors.append(row['sample_id']+':hash')
 with Image.open(p) as im:
  if im.size!=(int(row['width']),int(row['height'])):errors.append(row['sample_id']+':size')
  im.verify()
 if not (r/row['source_xml']).exists():errors.append(row['sample_id']+':source_xml')
for doc in r.glob('*.md'):
 for target in re.findall(r'\]\(([^)]+)\)',doc.read_text(encoding='utf-8')):
  if not target.startswith(('https://','http://')) and not (doc.parent/target).exists():errors.append(doc.name+':broken_link:'+target)
pre=json.loads((r/'reports/deployment_preflight.json').read_text(encoding='utf-8'))
assert hashlib.sha256(Path(pre['onnx_path']).read_bytes()).hexdigest()==pre['onnx_sha256']
out={'passed':not errors,'checked_candidate_images':len(rows),'all_image_hashes_dimensions_decode_and_source_xml_checked':True,'markdown_local_links_checked':True,'deployment_onnx_sha_checked':True,'errors':errors}
(r/'reports/delivery_integrity.json').write_text(json.dumps(out,indent=2),encoding='utf-8');print(json.dumps(out,indent=2));assert not errors
