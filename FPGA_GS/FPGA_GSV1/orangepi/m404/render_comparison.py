import json,sys
from pathlib import Path
import cv2,numpy as np
from PIL import Image
from overlay import tile
root=Path(__file__).resolve().parent;folder=root/'evidence/comparison'
def annotate(raw,objects,title):
 h,w=raw.shape[:2];width=1280;out=cv2.resize(raw,(width,round(h*width/w)));s=width/w
 for obj in objects:
  x0,y0,x1,y1=np.round(np.array(obj['box'])*s).astype(int);cv2.rectangle(out,(x0,y0),(x1,y1),(60,255,80),2)
 pil=Image.fromarray(cv2.cvtColor(out,cv2.COLOR_BGR2RGB))
 for obj in objects:
  x0,y0=np.round(np.array(obj['box'][:2])*s).astype(int);text=tile(obj['label']+' '+str(round(obj['confidence']*100))+'%',20,(255,255,255));bg=Image.new('RGBA',text.size,(0,0,0,200));bg.alpha_composite(text);pil.paste(bg,(max(0,min(width-text.width,x0)),max(28,y0-25)),bg)
 text=tile(title,22,(255,230,60));pil.paste(text,(8,0),text)
 return cv2.cvtColor(np.array(pil),cv2.COLOR_RGB2BGR)
for p in folder.glob('SC_*.json'):
 row=json.loads(p.read_text());base=folder/f"{row['video'][:-4]}_{row['seconds']}";raw=cv2.imread(str(base)+'_raw.jpg')
 if raw is None:continue
 cv2.imwrite(str(base)+'_onnx.jpg',annotate(raw,row['onnx_objects'],'原始浮点ONNX / CPU'))
 cv2.imwrite(str(base)+'_npu.jpg',annotate(raw,row['rknn']['objects'],'部署INT8 RKNN / NPU'))
failure=root/'evidence/failure_comparison.json'
if failure.exists():
 for row in json.loads(failure.read_text()):
  base=root/'evidence/runtime'/row['snapshot'];raw=cv2.imread(str(base)+'_raw.jpg')
  for backend,objects in [('onnx',row['cpu']),('npu',row['npu']['objects'])]:
   cv2.imwrite(str(root/'evidence'/row['snapshot'])+'_'+backend+'.jpg',annotate(raw,objects,backend+' / 真实失败样例，未修饰'))
