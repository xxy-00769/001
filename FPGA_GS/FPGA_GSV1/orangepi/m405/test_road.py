from road import RoadModel
import cv2,time,json
m=RoadModel();im=cv2.imread('m405/evidence/probe_raw.jpg')
for i in range(3):
 t=time.perf_counter();r,masks=m.infer(im);print(json.dumps(dict(ms=1000*(time.perf_counter()-t),stage=r['stage_ms'],ego=r['ego'])),flush=True)
cv2.imwrite('m405/evidence/probe320road.png',masks[0]);cv2.imwrite('m405/evidence/probe320lane.png',masks[1])
