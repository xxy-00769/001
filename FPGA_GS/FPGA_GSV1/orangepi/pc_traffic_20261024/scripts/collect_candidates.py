from pathlib import Path
from collections import Counter
from datetime import datetime
import zipfile,xml.etree.ElementTree as E,json,hashlib,csv,io
from PIL import Image,ImageDraw
r=Path(__file__).resolve().parents[1];z=zipfile.ZipFile(r/'data/s2tld_1080.zip');names=z.namelist();jpgs={Path(n).stem:n for n in names if n.lower().endswith('.jpg')}
allrows=[];last=None;seq=0
for name in sorted(n for n in names if n.endswith('.xml')):
 stem=Path(name).stem;t=datetime.strptime(stem[:19],'%Y-%m-%d %H_%M_%S');sec=t.timestamp()
 if last is None or sec-last>15:seq+=1
 last=sec
 a=E.fromstring(z.read(name));objects=[]
 for ob in a.findall('object'):
  bb=ob.find('bndbox');b=[int(float(bb.findtext(k))) for k in ['xmin','ymin','xmax','ymax']]
  objects.append({'source_class':ob.findtext('name'),'source_bbox_xyxy':b})
 allrows.append({'stem':stem,'time':sec,'sequence_candidate':f's2tld1080_seq_{seq:03d}','image_zip_path':jpgs.get(stem),'xml_zip_path':name,'source_objects':objects})
# Spread over the complete source timeline; do not pretend this is deduplication or final grouping.
N=min(400,len(allrows));idx=[round(i*(len(allrows)-1)/(N-1)) for i in range(N)];selected=[allrows[i] for i in idx]
(r/'data/candidate_images').mkdir(exist_ok=True);(r/'data/source_annotations').mkdir(exist_ok=True)
rows=[];classes=Counter();sides=Counter();bright=Counter();seen={};dups=[]
for i,a in enumerate(selected):
 raw=z.read(a['image_zip_path']);im=Image.open(io.BytesIO(raw)).convert('RGB');sha=hashlib.sha256(raw).hexdigest()
 if sha in seen:dups.append([seen[sha],a['stem']])
 seen[sha]=a['stem'];out=r/'data/candidate_images'/f's2tld1080_{i:04}.jpg';out.write_bytes(raw)
 xml=r/'data/source_annotations'/f's2tld1080_{i:04}.xml';xml.write_bytes(z.read(a['xml_zip_path']))
 gray=im.resize((32,32)).convert('L');mean=sum(gray.getdata())/1024;bright['low_mean_luminance' if mean<55 else 'other']+=1
 for ob in a['source_objects']:
  classes[ob['source_class']]+=1;b=ob['source_bbox_xyxy'];s=min(b[2]-b[0],b[3]-b[1]);sides['<8' if s<8 else '8-15' if s<16 else '16-31' if s<32 else '32+']+=1
 row={'sample_id':out.stem,'image_path':str(out.relative_to(r)),'source_xml':str(xml.relative_to(r)),'source_member':a['image_zip_path'],'sha256':sha,'width':im.width,'height':im.height,'source_classes':';'.join(sorted(set(o['source_class'] for o in a['source_objects']))),'source_object_count':len(a['source_objects']),'sequence_candidate':a['sequence_candidate'],'group_id':'','group_status':'unverified','split':'unassigned','review_status':'unreviewed','reviewer_1':'','reviewer_2':'','annotation_file':'','license_status':'verified','clean_original':'pending_visual_review','mean_luminance':round(mean,2),'night_status':'unreviewed','negative_regions_status':'unreviewed','arrow_status':'unreviewed'}
 rows.append(row)
with (r/'data/candidates.csv').open('w',newline='',encoding='utf-8-sig') as f:
 w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
(r/'data/source_candidate_annotations.json').write_text(json.dumps(selected,ensure_ascii=False,indent=2),encoding='utf-8')
stat={'archive_images':len(jpgs),'archive_xmls':len(allrows),'selected_images':len(rows),'sampling':'uniform timeline index for candidate review only; NOT final dedup or split','source_class_counts':dict(classes),'source_box_short_side_bins':dict(sides),'luminance_proxy_not_day_night_labels':dict(bright),'candidate_sequence_count':seq,'selected_candidate_sequences':len(set(x['sequence_candidate'] for x in rows)),'exact_duplicate_pairs':dups,'qualified_images':0,'all_review_pending':True,'unknown_source_box_definition':'Source boxes require visual check and possible reannotation to physical body; source color not accepted automatically.'}
(r/'reports/data_audit.json').write_text(json.dumps(stat,ensure_ascii=False,indent=2),encoding='utf-8')
# Representative contact sheets, each with 20 source images, not every image reviewed.
for page in range(2):
 can=Image.new('RGB',(1600,1050),'white');d=ImageDraw.Draw(can)
 for j in range(20):
  k=round((j+page*20)*(len(rows)-1)/39);im=Image.open(r/rows[k]['image_path']);im.thumbnail((392,180));x=(j%4)*400;y=(j//4)*210
  can.paste(im,(x,y+24));d.text((x+4,y+4),rows[k]['sample_id']+' '+rows[k]['source_classes'],fill='black')
 can.save(r/'artifacts'/f's2tld_contact_{page+1}.jpg')
print(json.dumps(stat,ensure_ascii=False,indent=2))
