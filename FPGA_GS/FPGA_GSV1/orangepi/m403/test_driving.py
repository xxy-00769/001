"""Rule-only simulated perceptions. These are not real visual accuracy tests."""
import unittest,time
from driving import Driving
def obs(light='UNKNOWN',left='UNKNOWN',right='UNKNOWN',actions=('straight',)):
 return dict(signal=dict(state=light,confidence=.9,actions=list(actions)),lanes={s:dict(state=v,confidence=.9,adjacent_lane_confirmed=True,reason='测试证据不足') for s,v in [('left',left),('right',right)]})
class Rules(unittest.TestCase):
 def setUp(self):self.d=Driving();self.t=time.monotonic()
 def update(self,o,age=0,dt=0):return self.d.update(o,age,self.t+dt)
 def test_red_stop_green_start(self):
  self.assertEqual(self.update(obs('RED'))['motion'],'STOPPED');self.assertIsNone(self.d.alarm)
  self.assertEqual(self.update(obs('GREEN'))['motion'],'MOVING')
 def test_red_ordinary_and_forced_are_separate(self):
  self.d.command(dict(intent='straight'),self.t);self.update(obs('RED'));self.assertIsNone(self.d.alarm)
  self.d.command(dict(intent='straight',force=True),self.t);self.assertIsNotNone(self.update(obs('RED'))['alarm'])
 def test_lane_independent_of_signal(self):
  self.d.command(dict(mode='lane',intent='left'),self.t)
  self.assertEqual(self.update(obs('UNKNOWN',left='DASHED'))['motion'],'CHANGE_LEFT')
 def test_solid_ordinary_and_forced(self):
  self.d.command(dict(mode='lane',intent='right'),self.t)
  self.assertEqual(self.update(obs(right='SOLID'))['motion'],'STRAIGHT');self.assertIsNone(self.d.alarm)
  self.d.command(dict(intent='right',force=True),self.t);self.assertIsNotNone(self.update(obs(right='SOLID'))['alarm'])
 def test_dashed_without_neighbor_is_unknown(self):
  self.d.command(dict(mode='lane',intent='right'),self.t);o=obs(right='DASHED');o['lanes']['right']['adjacent_lane_confirmed']=False
  self.assertEqual(self.update(o)['suggestion'],'UNKNOWN');self.assertEqual(self.d.motion,'STRAIGHT')
 def test_unknown_stale_mismatch_never_allow(self):
  self.assertEqual(self.update(obs('GREEN',actions=('left',)))['suggestion'],'UNKNOWN')
  self.assertEqual(self.update(obs('GREEN'),age=.6)['motion'],'STOPPED')
  self.d.command(dict(mode='lane',intent='left',force=True),self.t)
  self.assertEqual(self.update(obs())['suggestion'],'UNKNOWN');self.assertIsNone(self.d.alarm)
 def test_stop_priority(self):
  self.d.command(dict(intent='straight',force=True),self.t);self.update(obs('RED'))
  self.d.command(dict(intent='stop',force=True),self.t);self.assertEqual(self.update(obs('GREEN'))['motion'],'STOPPED');self.assertIsNone(self.d.alarm)
 def test_alarm_latches_and_expires_to_stop(self):
  self.d.command(dict(intent='straight',force=True),self.t);self.update(obs('RED'))
  self.assertIsNotNone(self.update(obs('GREEN'),dt=1)['alarm'])
  self.assertIsNone(self.update(obs('RED'),dt=5.1)['alarm']);self.assertEqual(self.d.intent,'stop');self.assertFalse(self.d.forced)
 def test_reset_and_clear(self):
  self.d.command(dict(intent='straight',force=True),self.t);self.update(obs('RED'));self.d.reset();self.assertIsNone(self.d.alarm);self.assertEqual(self.d.intent,'auto')
  self.d.command(dict(clear_alarm=True),self.t);self.assertEqual(self.d.intent,'stop')
if __name__=='__main__':unittest.main(verbosity=2)
