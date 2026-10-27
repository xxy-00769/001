"""Build the independent release from the preserved r2 source, never alter r2."""
from pathlib import Path
import shutil
HERE=Path(__file__).resolve().parent;BASE=HERE.parent/'m405r2'
for name in ('demo.py','demo_ops.py','overlay.py','driving.py','road.py','lane_semantics.py','index.html'):
 (HERE/name).write_bytes((BASE/name).read_bytes())
p=HERE/'demo.py';s=p.read_text(encoding='utf-8').replace('M4-05-r2','M4-06-r1').replace('m405r2/','m406/')
s=s.replace('from legacy_perception import Perception','from traffic import AsyncLights,fresh')
s=s.replace("self.perception=Perception(self.scenes[self.video]);",'self.lights=AsyncLights();self.lights.reset(0);self.show_lights=True;')
# Only init occurrence creates worker; reset clears the existing one.
s=s.replace('self.lights=AsyncLights();self.lights.reset(0);self.show_lights=True;self.obs=None;', 'self.lights.reset(self.epoch);self.obs=None;')
s=s.replace("published=copy.deepcopy(self.obs) if self.obs else None", "published=copy.deepcopy(self.obs) if self.obs else None\n   if published:published['traffic']=fresh(published.get('traffic'),now,self.epoch)")
s=s.replace('road=self.road.metrics(),show_road=', 'traffic=self.lights.metrics(),show_lights=self.show_lights,road=self.road.metrics(),show_road=')
s=s.replace("if 'show_road' in data:","if 'show_lights' in data:self.show_lights=bool(data['show_lights']);self.command_revision+=1\n   if 'show_road' in data:")
s=s.replace("raise ValueError('本版仅使用已核对的灯体外壳和方向标定；不接受只有颜色区域的放行标定')", "raise ValueError('自动交通灯模式禁止人工灯区/控制方向标定')")
s=s.replace('show_lane=self.show_lane)', 'show_lane=self.show_lane,show_lights=self.show_lights)')
s=s.replace(';perception=self.perception','')
start=s.index('    # Old calibrated signal/line-type algorithm')
end=s.index("    obs['detection']=",start)
s=s[:start]+'''    # Remove obsolete manual signal/template inference and redundant Hough.
    # r2 model road/lane and six-class object algorithms stay unchanged.
    legacy_at=decoded
    obs=dict(signal=dict(state='UNKNOWN',actions=[],confidence=0,reason='自动灯组控制归属未知'),lanes={},stage_ms={})
'''+s[end:]
s=s.replace("    obs['detection']['age_reference_monotonic']=time.monotonic()", "    obs['detection']['age_reference_monotonic']=time.monotonic()\n    obs['traffic']=self.lights.update(image,epoch,cursor,decoded,obs['detection'].get('objects',[]))")
s=s.replace("stage.update(**obs['detection']['stage_ms']);", "stage.update(**obs.get('traffic',{}).get('stage_ms',{}));stage.update(**obs['detection']['stage_ms']);")
s=s.replace("self.stop.set();self.road.close();", "self.stop.set();self.lights.close();self.road.close();")
s=s.replace("time.monotonic()-obs.get('road',{}).get('decoded_monotonic',0)>.5)","time.monotonic()-obs.get('road',{}).get('decoded_monotonic',0)>.5,time.monotonic()-obs.get('traffic',{}).get('decoded_monotonic',0)>.6)")
p.write_text(s,encoding='utf-8')
p=HERE/'demo_ops.py';p.write_text(p.read_text(encoding='utf-8').replace('m405r2','m406').replace('M4-05-r2','M4-06-r1'),encoding='utf-8')
p=HERE/'driving.py';s=p.read_text(encoding='utf-8').replace("self.mode='lane'", "self.mode='intersection'")
s=s.replace("  if self.mode!='lane' or self.intent=='stop':return super().update(observation,age,now)",'''  if self.intent=='stop':return super().update(observation,age,now)
  if self.mode=='intersection':
   if self.alarm and now>=self.alarm_until:self.alarm=None;self.forced=False;self.intent='stop'
   self.motion='STOPPED';self.suggestion='UNKNOWN'
   traffic=(observation or {}).get('traffic',{});lights=traffic.get('lights',[])
   if now-traffic.get('decoded_monotonic',-1e9)>.6:
    self.reason='交通灯证据已过期或等待检测；不自动放行';return self.snapshot()
   # Production r1 never asserts this relation. Keep the conditional rules
   # separate and testable; a colored lamp alone cannot enter this branch.
   relevant=[b for b in lights if b.get('control_relation')=='CONFIRMED' and self.lane in b.get('controls',[]) and b.get('kind')=='VEHICLE']
   colors={b.get('color') for b in relevant}
   if colors=={'RED'}:
    self.suggestion='STOP';self.reason='相关红灯：模拟停车'
    if self.forced:self.motion='MOVING';self.warn('闯红灯模拟告警',now)
   elif colors=={'GREEN'}:
    self.suggestion='SIGNAL_PERMITS';self.reason='信号允许；其他规则及交通安全仍需确认'
   else:self.reason='灯色已识别，控制关系未知；不自动放行' if any(b.get('color') in ('RED','GREEN','YELLOW') for b in lights) else '没有可靠灯态；未检出不代表无信号或可通行'
   return self.snapshot()''')
p.write_text(s,encoding='utf-8')
p=HERE/'overlay.py';s=p.read_text(encoding='utf-8');s=s.replace('import cv2,numpy as np','import cv2,numpy as np\nimport time,base64,io\nfrom traffic import fresh,CN')
s=s.replace('from PIL import Image,ImageDraw,ImageFont','from PIL import Image,ImageDraw,ImageFont')
start=s.index(" for c in sig.get('candidates',[]):");end=s.index(' # Human/vehicle model',start)
s=s[:start]+s[end:]
start=s.index(" if sig.get('candidates'):");end=s.index(' out=cv2.cvtColor(np.array(pil)',start)
s=s[:start]+''' if obs.get('show_lights',True):
  tl=fresh(obs.get('traffic'),time.monotonic());lights=tl.get('lights',[]);pd=ImageDraw.Draw(pil)
  colors={'RED':(255,75,65),'YELLOW':(255,210,40),'GREEN':(60,255,140),'UNKNOWN':(185,190,205)}
  for n,b in enumerate(lights):
   x0,y0,x1,y1=(np.asarray(b['box'])*[ww/w,hh/h,ww/w,hh/h]).astype(int);co=colors.get(b['color'],colors['UNKNOWN'])
   pd.rectangle((x0-2,y0-2,x1+2,y1+2),outline=co,width=max(2,round(2*s)))
   text('#'+str(b['id'])+' '+CN[b['color']],max(2,min(535,x0/s)),max(66,min(hh/s-120,y0/s-20)),14,co)
  # Source-frame crop, not current raw under an old box. The card declares age.
  for n,b in enumerate(lights[:2]):
   if not b.get('thumbnail_jpeg'):continue
   crop=thumbnail(b['thumbnail_jpeg']);crop=crop.resize((int(112*s),int(46*s)),Image.Resampling.NEAREST)
   xx,yy=int((400+n*120)*s),int(78*s);pil.paste(crop,(xx,yy));pd.rectangle((xx,yy,xx+int(112*s),yy+int(46*s)),outline=colors.get(b['color'],(190,190,190)),width=2)
   text('#'+str(b['id'])+' '+CN[b['color']]+' / 灯型未知',400+n*120,125,11,colors.get(b['color'],(190,190,190)))
  text('交通灯 '+(' / '.join('#'+str(b['id'])+CN[b['color']] for b in lights[:3]) or ('已过期' if tl.get('expired') else '未可靠检出')),8,67,15,(255,230,140))
  text('控制关系未知 · 不自动放行',8,88,13,(255,220,175))
  # Numeric metadata uses fast glyphs below, not uncached CJK every frame.
  changes=[c for c in tl.get('transitions',[]) if time.monotonic()-c['at_monotonic']<3]
  if changes:
   c=changes[-1];text('灯态变化 #'+str(c['id'])+' '+CN[c['previous']]+' → '+CN[c['current']],8,109,14,(255,230,140))
'''+s[end:]
s=s.replace(" return out", " if obs.get('show_lights',True):\n  tl=fresh(obs.get('traffic'),time.monotonic());cv2.putText(out,'TL src %s | age %sms'%(tl.get('source_frame_id','--'),tl.get('age_ms','--')),(round(320*s),round(152*s)),cv2.FONT_HERSHEY_SIMPLEX,.36*s,(230,230,230),max(1,round(s)),cv2.LINE_AA)\n return out")
s+='\n@lru_cache(maxsize=24)\ndef thumbnail(data):return Image.open(io.BytesIO(base64.b64decode(data))).convert("RGB")\n'
p.write_text(s,encoding='utf-8')
p=HERE/'index.html';s=p.read_text(encoding='utf-8').replace('M4-05-r2','M4-06-r1').replace('道路智驾演示','交通灯感知演示')
s=s.replace('<a href="/raw.jpg"', '<label><input id="traffic-layer" type="checkbox" checked>交通灯与灯区放大</label><a href="/raw.jpg"')
s=s.replace('<div class="stats" id="performance">', '<div class="stats" id="traffic-performance"></div><div class="stats" id="performance">')
s=s.replace("SIGNAL_PERMITS:","SIGNAL_PERMITS:")
s=s.replace("REVIEW:'需核实交通'", "REVIEW:'需核实交通',SIGNAL_PERMITS:'信号允许，仍需其他规则'")
anchor=" let d=s.driving;"
s=s.replace(anchor,""" let tr=s.perception?.traffic||{},tm=s.traffic||{},colors={RED:'红',GREEN:'绿',YELLOW:'黄',UNKNOWN:'不可判',OFF:'熄灭'};$('traffic-layer').checked=s.show_lights;$('traffic-performance').textContent='交通灯 CPU自动灯壳/灯色 · 实际 '+(tm.update_fps||0)+' Hz / 目标8Hz · 来源帧 '+(tr.source_frame_id??'—')+' / 年龄 '+(tr.age_ms??'—')+' ms · 跳过观测 '+(tm.skipped_source_observations||0)+' · '+((tr.lights||[]).map(b=>'#'+b.id+' '+colors[b.color]+'（圆/箭头未知，控制关系未知）').join('；')||tr.reason||'未可靠检出')+'。未检出不代表没有交通灯；不自动放行。';
"""+anchor)
s=s.replace("$('road-mask').onchange", "$('traffic-layer').onchange=()=>control({show_lights:$('traffic-layer').checked});$('road-mask').onchange")
s=s.replace('<span>本轮观察片段：</span>', '<span>交通灯观察（定位按钮不参与识别）：</span><button data-scene="red">夜间红灯</button><button data-scene="change">红转绿</button><button data-scene="negative">尾灯负样本</button>')
s=s.replace('const scenes={clear:',"const scenes={red:{video:'SC_YJ.mp4',seek:92,mode:'intersection'},change:{video:'SC_YJ.mp4',seek:101,mode:'intersection'},negative:{video:'SC_YJ2.mp4',seek:42,mode:'intersection'},clear:")
s=s.replace('<details><summary>方法、计数与限制</summary>', '<details><summary>方法、计数与限制</summary><p>自动交通灯结果与旧人工灯区/方向标定完全隔离。灯色与灯壳证据分别输出，600ms失效；新灯态连续两次确认，变化时先不可判。圆灯/箭头、行人灯类别与控制归属尚未可靠实现，因此本版不自动放行。OFF不以检测缺失推断。</p>')
p.write_text(s,encoding='utf-8')
print('independent m406 integration written')
