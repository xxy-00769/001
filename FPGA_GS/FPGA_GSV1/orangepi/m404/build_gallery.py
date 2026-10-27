from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,hashlib
p=Path('orangepi/m404');root=p/'evidence/final/native'
canvas=Image.new('RGB',(1280,776),(10,18,27));d=ImageDraw.Draw(canvas)
for i,name in enumerate(['SC_BT.mp4','SC_BT2.mp4','SC_YJ.mp4','SC_YJ2.mp4']):
 r=json.loads((p/'evidence/final'/f'{name}_640_snapshot.json').read_text(encoding='utf-8'))
 f=root/(r['snapshot']+'_overlay.jpg');im=Image.open(f).convert('RGB');im.thumbnail((640,360));x=(i%2)*640;y=(i//2)*388;canvas.paste(im,(x,y+28));d.text((x+8,y+5),name+' / '+str(round(r['status']['position'],2))+'s',fill='white')
canvas.save(p/'evidence/four_video_detection.jpg',quality=92)
# Historical comparison's nominal seek counter was not a native PTS frame id.
# Preserve measured outputs, explicitly identify the saved input by its SHA256.
folder=p/'evidence/comparison'
for f in list(folder.glob('SC_*.json'))+[folder/'summary.json',p/'evidence/model_comparison.json']:
 rows=json.loads(f.read_text(encoding='utf-8'));many=isinstance(rows,list);rows=rows if many else [rows]
 for row in rows:
  raw=folder/(row['video'][:-4]+'_'+str(row['seconds'])+'_raw.jpg');ident='jpeg-sha256:'+hashlib.sha256(raw.read_bytes()).hexdigest()
  row['image_identity']=ident;row['time_note']='Nominal OpenCV seek, not exact VFR PTS. Both models used the same decoded array; JPEG SHA identifies saved evidence.'
  row['rknn']['frame_id']=ident
  for x in row['rknn']['objects']:x['detection_frame_id']=ident
 f.write_text(json.dumps(rows if many else rows[0],ensure_ascii=False,indent=2),encoding='utf-8')
