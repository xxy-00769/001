from pathlib import Path
from PIL import Image
import csv,json
r=Path(__file__).resolve().parents[1];rows=list(csv.DictReader((r/'data/candidates.csv').open(encoding='utf-8-sig')));hashes=[]
for row in rows:
 im=Image.open(r/row['image_path']).convert('L').resize((17,8));p=list(im.getdata());bits=0
 for y in range(8):
  for x in range(16):bits=(bits<<1)|int(p[y*17+x]>p[y*17+x+1])
 hashes.append(bits)
pairs=[]
for i,a in enumerate(hashes):
 for j in range(i):
  distance=(a^hashes[j]).bit_count()
  if distance<=6:pairs.append({'a':rows[j]['sample_id'],'b':rows[i]['sample_id'],'dhash128_distance':distance,'same_candidate_sequence':rows[i]['sequence_candidate']==rows[j]['sequence_candidate'],'status':'manual_verification_required'})
(r/'reports/near_duplicate_candidates.json').write_text(json.dumps({'algorithm':'128-bit dHash; threshold6; proposals only, not definitive same-scene proof','pair_count':len(pairs),'pairs':pairs},indent=2),encoding='utf-8')
print('near duplicate candidate pairs',len(pairs))
