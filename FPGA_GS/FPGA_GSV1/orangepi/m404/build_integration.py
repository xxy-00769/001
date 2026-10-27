from pathlib import Path
import shutil
r=Path('orangepi');p=r/'m404'
s=(r/'m403/demo.py').read_text(encoding='utf-8')
s=s.replace('import cv2,numpy as np','import cv2,numpy as np\nimport sys\nsys.path.append(str(Path(__file__).resolve().parents[1]/"m403"))\nfrom detector import AsyncDetector')
s=s.replace("VERSION='M4-03-demo-r1'","VERSION='M4-04-r1'")
s=s.replace('self.driver=Driving();','self.detector=AsyncDetector();self.detector.reset(0);self.driver=Driving();')
s=s.replace('self.epoch+=1;','self.epoch+=1;self.detector.reset(self.epoch);')
s=s.replace("ROOT/'m403/evidence/runtime'","ROOT/'m404/evidence/runtime'")
s=s.replace("self.out.mkdir(exist_ok=True)","self.out.mkdir(parents=True,exist_ok=True)")
s=s.replace("ROOT/'m403/index.html'","ROOT/'m404/index.html'")
s=s.replace("sec=pts[cursor];obs=perception.analyze(image)","sec=pts[cursor];obs=perception.analyze(image)\n    obs['detection']=self.detector.update(image,epoch,cursor,decoded)")
s=s.replace("stage.update(decode=", "stage.update(**obs['detection']['stage_ms'])\n    stage.update(decode=")
s=s.replace('self.stop.set();self.server.shutdown()', 'self.stop.set();self.detector.close();self.server.shutdown()')
s=s.replace('driving=self.driver.snapshot(),perception=self.obs,',"driving=self.driver.snapshot(),perception=self.obs,detection=(self.obs or {}).get('detection'),")
(p/'demo.py').write_text(s,encoding='utf-8')
s=(r/'m403/overlay.py').read_text(encoding='utf-8')
needle=' # Three large directional arrows'
insert=''' # Human/vehicle model outputs use native-image coordinates; labels avoid driving panels.
 targets=[]
 for obj in obs.get('detection',{}).get('objects',[]):
  x0,y0,x1,y1=(np.array(obj['box'])*[ww/w,hh/h,ww/w,hh/h]).astype(int)
  color=(255,190,30) if obj['class_id']==0 else (80,240,100)
  tracked=obj['source']!='detection'
  if tracked:
   for xx in range(x0,x1,max(1,int(12*s))):
    cv2.line(out,(xx,y0),(min(x1,xx+int(7*s)),y0),color,max(1,int(2*s)));cv2.line(out,(xx,y1),(min(x1,xx+int(7*s)),y1),color,max(1,int(2*s)))
   cv2.line(out,(x0,y0),(x0,y1),color,max(1,int(s)));cv2.line(out,(x1,y0),(x1,y1),color,max(1,int(s)))
  else:cv2.rectangle(out,(x0,y0),(x1,y1),color,max(1,int(2*s)))
  targets.append((obj,max(0,min(ww-int(150*s),x0)),max(int(100*s),min(hh-int(82*s),y0-int(20*s)))))
'''
s=s.replace(needle,insert+needle)
s=s.replace(" text('本地录像 / 模拟车辆 · '+video", " text('本地录像 / 模拟车辆 · '+video")
s=s.replace(" text('灯色 '+", " for obj,tx,ty in targets:\n  label=obj['label']+' '+str(round(obj['confidence']*100))+'%'+(' 跟踪' if obj['source']!='detection' else '')\n  im=tile(label,round(13*s),(255,255,255));bg=Image.new('RGBA',im.size,(0,0,0,210));bg.alpha_composite(im);pil.paste(bg,(tx,ty),bg)\n det=obs.get('detection',{});text('NPU 人车 '+str(det.get('count',0))+' · 检测 '+str(det.get('detection_fps',0))+'fps',360,3,13,(140,255,170))\n text('灯色 '+")
(p/'overlay.py').write_text(s,encoding='utf-8')
s=(r/'m403/index.html').read_text(encoding='utf-8').replace('M4-03','M4-04-r1')
s=s.replace('车辆/行人/斑马线本轮仅列素材，不提供识别结果。','人车目标来自YOLOv8n模型；车道与灯色仍为旧算法及场景标定，斑马线未支持。')
s=s.replace('CPU基线，NPU未启用。','目标检测：RKNN/NPU · YOLOv8n COCO 640×640 INT8；六类人车。分数为模型置信度，不是准确率。虚线框为短时光流延续，最长350ms；锥桶、施工围栏、电动车细分未支持。')
s=s.replace("let m=window.m403Metrics();$('performance').textContent=", "let m=window.m403Metrics();let dt=s.detection||{};$('performance').textContent='RKNN/NPU · 检测 '+(dt.detection_fps||0).toFixed(2)+' fps · 有效目标 '+(dt.count||0)+'（跟踪 '+(dt.held_count||0)+'） · '+")
(p/'index.html').write_text(s,encoding='utf-8')
