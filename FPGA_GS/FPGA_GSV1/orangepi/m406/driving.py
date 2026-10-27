"""r2 crossing advice. No traffic clearance or automatic lane change."""
import importlib.util,time
from pathlib import Path
sp=importlib.util.spec_from_file_location('preserved_driving',Path(__file__).parent.parent/'m403/driving.py')
old=importlib.util.module_from_spec(sp);sp.loader.exec_module(old)

class Driving(old.Driving):
 def reset(self):
  super().reset();self.mode='intersection'
 def update(self,observation,age,now):
  if self.intent=='stop':return super().update(observation,age,now)
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
   return self.snapshot()
  if self.alarm and now>=self.alarm_until:self.alarm=None;self.forced=False;self.intent='stop';return super().update(observation,age,now)
  self.motion='STRAIGHT';self.suggestion='KEEP'
  if self.intent not in ('left','right'):
   self.reason='模拟直行；本轮仅提供跨线依据，无自动驾驶控制';return self.snapshot()
  rd=(observation or {}).get('road',{});semantic=rd.get('lane_semantics',{});side=semantic.get(self.intent,{})
  # Check the road source time itself, including paused control requests.
  road_age=now-rd.get('decoded_monotonic',-1e9)
  if age>.5 or road_age>.5 or rd.get('ego',{}).get('state')!='DETECTED':
   self.suggestion='UNKNOWN';self.reason='边界证据不足或超过500ms失效；保持直行';return self.snapshot()
  if side.get('state')=='SOLID':
   self.reason='对应侧明确实线：禁止跨越，保持直行'
   if self.forced:self.warn('跨实线模拟告警（无真实控制）',now)
  elif side.get('state')=='DASHED' and side.get('adjacent',{}).get('state')=='EXISTS':
   self.suggestion='REVIEW';self.reason='边界可跨越；仍需确认目标车道交通及方向，不代表安全变道'
  else:
   self.suggestion='UNKNOWN';self.reason=('虚线但相邻车道证据不足' if side.get('state')=='DASHED' else side.get('reason','边界未知'))+'；保持直行'
  return self.snapshot()
