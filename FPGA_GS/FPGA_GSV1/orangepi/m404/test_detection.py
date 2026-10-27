"""Targeted deployment checks; no old driving/UDP/algorithm suite."""
import unittest
import numpy as np
from detector import prepare,postprocess,AsyncDetector
class DetectionChecks(unittest.TestCase):
 def test_rgb_padding(self):
  image=np.zeros((360,640,3),np.uint8);image[:]=[1,2,3]
  x,tr=prepare(image);self.assertEqual(x.shape,(1,640,640,3));self.assertEqual(x[0,140,0].tolist(),[3,2,1]);self.assertEqual(x[0,0,0].tolist(),[114]*3);self.assertEqual(tr,(1,1,0,140))
 def test_empty_outputs(self):
  out=[]
  for size in [80,40,20]:out.extend([np.zeros((1,64,size,size),np.float32),np.zeros((1,80,size,size),np.float32),np.zeros((1,1,size,size),np.float32)])
  self.assertEqual(postprocess(out,(1,1,0,140),(360,640,3)),[])
 def test_best_class_not_relabelled(self):
  out=[]
  for size in [80,40,20]:out.extend([np.zeros((1,64,size,size),np.float32),np.zeros((1,80,size,size),np.float32),np.zeros((1,1,size,size),np.float32)])
  out[1][0,4,30,30]=.9;out[1][0,0,30,30]=.6
  self.assertEqual(postprocess(out,(1,1,0,140),(360,640,3)),[],'airplane must not become person')
 def test_epoch_reset_discards_result(self):
  import threading,collections
  d=AsyncDetector.__new__(AsyncDetector);d.lock=threading.Lock();d.latest=('old',);d.pending=('old',);d.epoch=0;d.times=collections.deque()
  d.reset(1);self.assertIsNone(d.latest);self.assertIsNone(d.pending);self.assertEqual(d.epoch,1)
if __name__=='__main__':unittest.main()
