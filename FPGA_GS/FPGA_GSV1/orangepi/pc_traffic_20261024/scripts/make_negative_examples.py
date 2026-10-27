from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json,csv
r=Path(__file__).resolve().parents[1];font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',19)
cases=[
 ('taillight','s2tld1080_0307',[1403,842,1444,887],'尾灯：交通灯检测硬负样本'),
 ('led_text','s2tld1080_0266',[1422,129,1678,175],'辅助LED文字：源wait_on，不是灯体'),
 ('reflection','s2tld1080_0174',[1250,700,1560,1020],'路面反光：不能当灯色证据'),
 ('arrow','s2tld1080_0307',[1138,310,1209,345],'可辨左箭头；颜色须看原图独立复核'),
]
can=Image.new('RGB',(1100,950),'white');d=ImageDraw.Draw(can);ann=[]
for i,(typ,sample,box,label) in enumerate(cases):
 im=Image.open(r/'data/candidate_images'/f'{sample}.jpg');crop=im.crop(box);crop.thumbnail((900,180));
 if typ!='reflection':crop=im.crop(box).resize((min(900,(box[2]-box[0])*3),min(180,(box[3]-box[1])*3)))
 y=i*235;d.text((10,y+5),label,font=font,fill='black');can.paste(crop,(30,y+42))
 ann.append({'sample_id':sample,'bbox_xyxy':box,'type':'hard_negative' if typ!='arrow' else 'arrow_example','category':typ,'review_status':'first_pass_pending_independent_review','complete_image_annotation':False,'source_annotation_is_not_ground_truth':True,'note':label,'color':'unknown' if typ=='arrow' else None,'arrow_direction':'left' if typ=='arrow' else None})
can.save(r/'artifacts/hard_negative_examples.png')
(r/'annotations/hard_negative_examples.json').write_text(json.dumps(ann,ensure_ascii=False,indent=2),encoding='utf-8')
print('negative regions and visible arrow example saved; pending independent review')

