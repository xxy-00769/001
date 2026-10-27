"""Synthetic safety/unit checks, never reported as visual accuracy."""
import time,unittest,threading
from unittest.mock import patch
import numpy as np
import traffic
from driving import Driving

class Checks(unittest.TestCase):
 def test_confirmation_and_transition(self):
  im=np.zeros((50,100,3),np.uint8);m=traffic.Lights(neural=False)
  b=dict(box=[10,10,50,25],color='RED',body_source='SYNTHETIC_TEST')
  with patch.object(traffic,'candidates',return_value=([b],{})),patch.object(traffic,'color_check',side_effect=lambda im,b:b):
   a=m.analyze(im,1,100,time.monotonic());z=m.analyze(im,1,101,time.monotonic())
   self.assertEqual(a['lights'][0]['color'],'UNKNOWN');self.assertEqual(z['lights'][0]['color'],'RED')
   b['color']='GREEN';a=m.analyze(im,1,102,time.monotonic());z=m.analyze(im,1,103,time.monotonic())
   self.assertEqual(a['lights'][0]['color'],'UNKNOWN');self.assertEqual(z['lights'][0]['color'],'GREEN');self.assertEqual(z['transitions'][0]['previous'],'RED')
   m.reset();self.assertEqual(m.tracks,[])
 def test_expiry_and_epoch(self):
  r=dict(decoded_monotonic=10,epoch=1,lights=[dict(color='RED',decoded_monotonic=10)],transitions=[])
  self.assertEqual(len(traffic.fresh(r,10.4,1)['lights']),1)
  self.assertEqual(traffic.fresh(r,10.61,1)['lights'],[])
  self.assertEqual(traffic.fresh(r,10.1,2)['lights'],[])
  self.assertEqual(len(r['lights']),1)
 def test_unknown_control_does_not_release(self):
  d=Driving();now=time.monotonic();obs=dict(signal=dict(state='GREEN',actions=['straight'],confidence=1),traffic=dict(decoded_monotonic=now,lights=[dict(color='GREEN',control_relation='UNKNOWN')]))
  for forced in (False,True):
   d.command(dict(intent='straight',force=forced),now);z=d.update(obs,0,now)
   self.assertEqual(z['motion'],'STOPPED');self.assertEqual(z['suggestion'],'UNKNOWN');self.assertIsNone(z['alarm'])
  d.command(dict(intent='stop'),now);self.assertEqual(d.update(obs,0,now)['suggestion'],'STOP')
 def test_confirmed_rule_is_separate(self):
  d=Driving();now=time.monotonic();b=dict(kind='VEHICLE',control_relation='CONFIRMED',controls=['straight'],color='RED');obs=dict(traffic=dict(decoded_monotonic=now,lights=[b]))
  self.assertEqual(d.update(obs,0,now)['motion'],'STOPPED')
  d.command(dict(intent='straight',force=True),now);self.assertIn('闯红灯',d.update(obs,0,now)['alarm'])
  d.command(dict(intent='stop'),now);self.assertIsNone(d.update(obs,0,now)['alarm'])
  b['color']='GREEN';d.command(dict(intent='auto'),now);self.assertEqual(d.update(obs,0,now)['suggestion'],'SIGNAL_PERMITS');self.assertEqual(d.motion,'STOPPED')
 def test_real_led_negative_and_two_green_heads(self):
  from pathlib import Path
  import cv2
  p=Path(__file__).parent/'evidence/failure_before_veto/GREEN_raw.jpg'
  if not p.exists():self.skipTest('Real regression fixture not copied')
  image=cv2.imread(str(p))
  # Developer visually reviewed real source frame 3233: LED text vs two lamps.
  self.assertTrue(traffic.dense_context(image,[287,49,369,81])[0])
  for box in ([1642,638,1712,666],[1485,636,1575,670]):
   self.assertFalse(traffic.dense_context(image,box)[0])
   self.assertEqual(traffic.color_check(image,dict(box=box,body_source='AUTO_CAPSULE_GEOMETRY',confidence=None))['color'],'GREEN')

if __name__=='__main__':unittest.main(verbosity=2)
