"""Keep M403 algorithms unchanged; do not change global OpenCV thread pools on HTTP reset."""
import collections
from pathlib import Path
import cv2
from perception import Perception as LegacyPerception
class Perception(LegacyPerception):
 def __init__(self,scene):
  self.scene=scene;self.votes={k:collections.deque(maxlen=5) for k in ('signal','left','right')};self.geometry={}
  cfg=scene.get('signal') or {};base=Path(__file__).resolve().parents[1]/'m403'
  self.template=cv2.imread(str(base/cfg['template']),0) if cfg.get('template') else None
  self.template_mask=cv2.imread(str(base/cfg['mask']),0) if cfg.get('mask') else None
