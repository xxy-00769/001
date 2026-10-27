"""Directed real-image evidence inspection, not a labelled accuracy benchmark."""
import pathlib,json,cv2,time
from perception import Perception
from driving import Driving
from overlay import draw
r=pathlib.Path(__file__).resolve().parents[1];out=r/'m403/evidence';scenes=json.loads((r/'m403/scenes.json').read_text());rows=[]
files=list(out.glob('SC_*.jpg'))+list(out.glob('YJ_scene_*.jpg'))
for p in files:
 if 'contact'in p.name or 'overlay'in p.name:continue
 video='SC_YJ.mp4' if p.name.startswith('YJ_scene_') else '_'.join(p.stem.split('_')[:2])+'.mp4'
 if video not in scenes:continue
 im=cv2.imread(str(p));per=Perception(scenes[video]);start=time.perf_counter()
 for _ in range(3):obs=per.analyze(im)
 driver=Driving();driver.mode='intersection' if video=='SC_YJ.mp4' else 'lane';driver.intent='left';drive=driver.update(obs,0,time.monotonic())
 cv2.imwrite(str(out/(p.stem+'_overlay.jpg')),draw(im,obs,drive,1280,video,0))
 rows.append(dict(file=p.name,signal=obs['signal'],lanes=obs['lanes'],stage=obs['stage_ms']))
 print(p.name,obs['signal']['state'],[(x,obs['lanes'][x]['state'],obs['lanes'][x]['coverage'],obs['lanes'][x]['segments'],obs['lanes'][x]['gaps']) for x in ('left','right')],flush=True)
(out/'image_probe.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
