import json,hashlib,csv,subprocess,sys,importlib.metadata as md
from pathlib import Path
root=Path(__file__).resolve().parents[1]; base=root.parent
files=[]
for folder in ['m406','m405r2','m404','m405','oneclick']:
 for p in sorted((base/folder).rglob('*')):
  if p.is_file() and not any(x in p.parts for x in ['__pycache__','vendor','research','evidence','backup','build_vendor']):
   files.append({'path':str(p.relative_to(base)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(root/'reports/protected_before.json').write_text(json.dumps(files,indent=2),encoding='utf-8')
imgs=[]
from PIL import Image,ImageOps,ImageDraw
paths=[base/'m406/evidence/exact_source/RED_raw.jpg',base/'m406/evidence/exact_source/GREEN_raw.jpg',base/'m406/evidence/auto/SC_BT_55_raw.jpg',base/'m406/evidence/auto/SC_YJ2_50_raw.jpg',base/'m406/evidence/failure_before_veto/GREEN_traffic.jpg',base/'m406/evidence/auto/SC_BT2_15_raw.jpg']
canvas=Image.new('RGB',(1200,1140),'#ffffff');d=ImageDraw.Draw(canvas)
for i,p in enumerate(paths):
 im=Image.open(p).convert('RGB'); im.thumbnail((590,340)); x=(i%2)*600;y=(i//2)*380
 canvas.paste(im,(x,y+28));d.text((x+5,y+5),p.parent.name+'/'+p.name,fill='black')
canvas.save(root/'artifacts/baseline_contact.jpg')
for p in sorted((base/'m406/evidence').rglob('*raw.jpg')):
 im=Image.open(p)
 imgs.append({'sample_id':p.parent.name+'/'+p.stem,'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'width':im.width,'height':im.height,'role':'development_regression_only','annotation_status':'unreviewed','license_status':'project_internal_rights_not_independently_verified','split':'regression'})
with (root/'data/baseline_inventory.csv').open('w',newline='',encoding='utf-8-sig') as f:
 w=csv.DictWriter(f,fieldnames=list(imgs[0]));w.writeheader();w.writerows(imgs)
print('raw evidence inventory',len(imgs),'protected',len(files))
