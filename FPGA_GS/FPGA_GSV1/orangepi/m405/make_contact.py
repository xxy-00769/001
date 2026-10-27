from PIL import Image,ImageDraw,ImageFont
from pathlib import Path
import json
base=Path('m405/evidence/audit');names=['SC_BT_5','SC_BT_20','SC_BT_32','SC_BT_57','SC_BT2_12','SC_YJ_20','SC_YJ_98','SC_YJ2_20'];out=Image.new('RGB',(960,len(names)*205),(15,20,27));d=ImageDraw.Draw(out);f=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',15)
for i,n in enumerate(names):
 if not (base/(n+'.json')).exists():continue
 meta=json.loads((base/(n+'.json')).read_text(encoding='utf-8'));g=meta['observation']['road']['ego'];d.text((5,i*205+1),n+' / '+g['state']+' / 原图 — 组合 — 道路模型掩码',font=f,fill='white')
 for j,suf in enumerate(['_raw.jpg','_overlay.jpg','_road.png']):
  im=Image.open(base/(n+suf)).convert('RGB').resize((320,180));out.paste(im,(j*320,i*205+25))
out.save('m405/evidence/audit_contact.jpg',quality=92)
