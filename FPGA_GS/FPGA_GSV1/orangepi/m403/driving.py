"""Persistent simulated vehicle state, separate from UDP RESULT TTL and actual actuators."""
import time
LABELS={'left':'左转','right':'右转','straight':'直行','stop':'停车','auto':'自动','force':'强制行驶'}
class Driving:
 def __init__(self):self.reset()
 def reset(self):
  self.mode='intersection';self.lane='straight';self.intent='auto';self.forced=False
  self.motion='STOPPED';self.suggestion='UNKNOWN';self.reason='等待新图像证据';self.alarm=None;self.alarm_until=0;self.command_id=0
 def command(self,data,now):
  if 'mode'in data:
   if data['mode'] not in ('intersection','lane'):raise ValueError('模式无效')
   self.reset();self.mode=data['mode']
  if 'lane'in data:
   if data['lane'] not in ('left','straight','right'):raise ValueError('车道无效')
   self.lane=data['lane'];self.intent='auto';self.forced=False;self.motion='STOPPED';self.alarm=None
  if 'intent'in data:
   intent=data['intent']
   if intent not in ('auto','left','right','straight','stop'):raise ValueError('驾驶请求无效')
   self.intent=intent;self.forced=bool(data.get('force',False)) and intent!='stop';self.command_id+=1
   if intent=='stop':self.motion='STOPPED';self.alarm=None;self.alarm_until=0
  if data.get('clear_alarm'):
   self.alarm=None;self.alarm_until=0;self.forced=False;self.intent='stop';self.motion='STOPPED'
 def update(self,observation,age,now):
  if self.alarm and now>=self.alarm_until:self.alarm=None;self.forced=False;self.intent='stop';self.motion='STOPPED'
  if self.intent=='stop':self.suggestion='STOP';self.reason='用户停车优先';self.motion='STOPPED';return self.snapshot()
  if observation is None or age>.5:
   self.suggestion='UNKNOWN';self.reason='感知已过期或尚无新图像';self.motion='STOPPED';return self.snapshot()
  if self.mode=='intersection':
   s=observation['signal'];relevant=self.lane in s.get('actions',[]) and s.get('confidence',0)>=.7
   if not relevant or s['state']not in ('RED','GREEN'):
    self.suggestion='UNKNOWN';self.motion='STOPPED'
    self.reason=('所选车道与标定灯组控制方向不匹配' if s.get('actions') and self.lane not in s['actions'] else s.get('reason','灯色证据不足'))
    return self.snapshot()
   if s['state']=='RED':
    self.suggestion='STOP';self.motion='MOVING' if self.forced else 'STOPPED';self.reason='相关红灯：普通请求保持停车'
    if self.forced:self.warn('闯红灯模拟告警',now)
   else:self.suggestion='ALLOW';self.motion='MOVING';self.reason='相关绿灯，模拟车辆起步'
  else:
   if self.intent not in ('left','right'):
    self.suggestion='KEEP';self.motion='STRAIGHT';self.reason='道路模式保持直行，不依赖绿灯';return self.snapshot()
   side=observation['lanes'][self.intent]
   if side['state']=='UNKNOWN' or side.get('confidence',0)<.7:
    self.suggestion='UNKNOWN';self.motion='STRAIGHT';self.reason=side.get('reason','对应侧边界未知');return self.snapshot()
   if side['state']=='DASHED':
    if not side.get('adjacent_lane_confirmed',False):
     self.suggestion='UNKNOWN';self.motion='STRAIGHT';self.reason='虚线候选但邻侧车道未确认，不能把路缘/路肩当可变车道';return self.snapshot()
    self.suggestion='ALLOW';self.motion='CHANGE_'+self.intent.upper();self.reason='虚线允许变道；邻车道人工标定' if side.get('adjacent_lane_source')=='MANUAL_SCENE_CALIBRATION' else '对应侧虚线且邻侧车道明确，模拟变道允许'
   else:
    self.suggestion='KEEP';self.motion='CHANGE_'+self.intent.upper() if self.forced else 'STRAIGHT';self.reason='对应侧实线：普通请求保持直行'
    if self.forced:self.warn('跨实线变道模拟告警',now)
  return self.snapshot()
 def warn(self,message,now):
  if self.alarm!=message:self.alarm=message;self.alarm_until=now+5
 def snapshot(self):
  return dict(mode=self.mode,lane=self.lane,intent=self.intent,forced=self.forced,motion=self.motion,suggestion=self.suggestion,reason=self.reason,alarm=self.alarm,alarm_remaining_seconds=round(max(0,self.alarm_until-time.monotonic()),1),command_id=self.command_id,alarm_policy='告警锁存5秒；到期取消强制并停车；停车/清除告警立即解除；切视频/跳转/循环重置',vehicle='SIMULATED_ONLY')
