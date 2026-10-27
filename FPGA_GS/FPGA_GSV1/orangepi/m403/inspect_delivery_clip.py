import cv2,json
from pathlib import Path
import numpy as np
R=Path(__file__).resolve().parent;path=R/'evidence/final_day_actual_operations.webm';cap=cv2.VideoCapture(str(path))
import subprocess
probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','packet=pts_time,duration_time','-of','json',str(path)]))
packets=probe['packets'];pts=[float(p['pts_time']) for p in packets];duration=max(float(p['pts_time'])+float(p.get('duration_time',0)) for p in packets)-min(pts)
decoded=[]
while True:
 ok,im=cap.read()
 if not ok:break
 decoded.append(cv2.resize(im,(640,360)))
assert decoded;frames=len(decoded);fps=frames/duration;tiles=[]
for index in np.linspace(0,frames-1,8).astype(int):
 im=decoded[index].copy();cv2.putText(im,f'actual recording decoded frame {index}',(8,350),0,.5,(255,255,255),1);tiles.append(im)
cv2.imwrite(str(R/'evidence/final_operations_contact.jpg'),np.vstack([np.hstack(tiles[i:i+2]) for i in range(0,8,2)]))
(R/'evidence/operation_clip_metadata.json').write_text(json.dumps(dict(fps=fps,frames=frames,duration_seconds=duration,source='browser canvas of actual original-file playback; not recognition accuracy or throughput benchmark')))
print(duration,frames)
