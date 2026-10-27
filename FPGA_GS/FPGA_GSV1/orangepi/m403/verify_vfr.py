"""Targeted native-VFR seek/loop check on the running offline service."""
import json,time,urllib.request
from pathlib import Path
R=Path(__file__).resolve().parent;URL='http://127.0.0.1:8080'
def status():return json.load(urllib.request.urlopen(URL+'/status.json',timeout=5))
def control(data):
 s=status();req=urllib.request.Request(URL+'/demo/control',data=json.dumps(data).encode(),headers={'Content-Type':'application/json','X-M4-Control-Token':s['control_token']})
 return json.load(urllib.request.urlopen(req,timeout=15))
start=status();control(dict(video='SC_YJ2.mp4',seek=76,playing=True,loop=True));deadline=time.monotonic()+45;at=None;after=None
while time.monotonic()<deadline:
 s=status()
 if s['video']=='SC_YJ2.mp4' and 76<=s['position']<78.05 and s['perception']:at=s
 if at and s['epoch']>at['epoch'] and s['position']<3 and s['perception']:after=s;break
 time.sleep(.1)
assert at and after,'VFR seek or natural loop did not recover'
assert start['instance']==after['instance'] and not after['error']
pts=json.loads((R/'SC_YJ2.mp4.pts.json').read_text());assert abs(pts[at['frame_id']]-at['position'])<.00001
for x in (start,at,after):x.pop('control_token',None)
out=dict(passed=True,method='real native SC_YJ2, seek 76s then natural loop, same service instance',before=start,at_76=at,after_loop=after)
(R/'evidence/vfr_seek_loop.json').write_text(json.dumps(out,ensure_ascii=False,indent=2))
control(dict(video='SC_YJ.mp4',seek=70,mode='intersection',lane='straight',playing=True))
print(json.dumps(dict(passed=True,instance=after['instance'],at=at['position'],after=after['position'],epoch_before=at['epoch'],epoch_after=after['epoch'])))
