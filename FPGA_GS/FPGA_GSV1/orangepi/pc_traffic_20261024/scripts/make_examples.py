from PIL import Image,ImageDraw,ImageFont
from pathlib import Path
import json,hashlib
r=Path(__file__).resolve().parents[1];b=r.parent/'m406/evidence';items=[]
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',18)
# Human-visible first-pass examples, never signed off as independently reviewed.
for color,boxes,emitters in [
 ('RED',[[1511,632,1581,660],[1648,635,1720,664]],[[1517,637,1539,656],[1655,639,1677,659]]),
 ('GREEN',[[1515,631,1587,660],[1661,633,1732,663]],[[1560,635,1580,656],[1702,638,1724,660]])]:
 p=b/'exact_source'/f'{color}_raw.jpg';im=Image.open(p)
 row={'id':color,'image_path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'image_size':[im.width,im.height],
 'source_video':'SC_YJ.mp4','source_frame_id':json.loads((b/'exact_source'/f'{color}.json').read_text(encoding='utf-8'))['source_frame_id'],
 'split':'regression','review_status':'first_pass_pending_independent_review','annotator':'Codex_visual_first_pass',
 'complete_image_annotation':False,'note':'Only two example housings are marked. Not exhaustive; forbidden as full-image training labels. Boxes redrawn after visual inspection, not accepted model outputs.', 'objects':[]}
 for j,(box,em) in enumerate(zip(boxes,emitters)):
  ident=f'{color}_body_{j+1}'
  row['objects'].append({'id':ident,'type':'body','bbox_xyxy':box,'kind':'motor_vehicle','layout':'horizontal','group_id':None,'occlusion':'none','truncated':False,'control_relation':'unknown','quality_flags':['glare']})
  row['objects'].append({'id':ident+'_emitter','parent_id':ident,'type':'emitter','bbox_xyxy':em,'state':color.lower(),'color_readable':True,'symbol':'unknown','arrow_direction':'unknown','unknown_reason':'saturation','quality_flags':['overexposure']})
 items.append(row)
canvas=Image.new('RGB',(1200,760),'white');d=ImageDraw.Draw(canvas)
for i,row in enumerate(items):
 im=Image.open(row['image_path']);crop=(1460,600,1770,700);scale=3.3
 thumb=im.crop(crop).resize((1023,330));x,y=100,45+i*370;canvas.paste(thumb,(x,y))
 d.text((10,y-32),f"{row['id']}：蓝框=灯体，橙框=发光区域；形状/控制归属未知；待独立复审",font=font,fill='black')
 for o in row['objects']:
  q=o['bbox_xyxy'];bb=[x+(q[0]-crop[0])*scale,y+(q[1]-crop[1])*scale,x+(q[2]-crop[0])*scale,y+(q[3]-crop[1])*scale]
  d.rectangle(bb,outline='#00aaff' if o['type']=='body' else '#ff9900',width=2)
canvas.save(r/'artifacts/annotation_examples.png')
(r/'annotations/examples.json').write_text(json.dumps({'schema_version':'0.1','status':'illustrative_not_gold','images':items},ensure_ascii=False,indent=2),encoding='utf-8')
print('wrote first-pass examples, not exhaustive labels')
