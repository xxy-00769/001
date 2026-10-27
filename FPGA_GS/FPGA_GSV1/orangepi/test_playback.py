"""Only the FILE_TEST clock/HTTP changes; no recognition or UDP regression."""
import unittest
from playback import PlaybackClock

class PlaybackTiming(unittest.TestCase):
    def setUp(self): self.clock=PlaybackClock(30,360,15,100)

    def test_native_frames_at_realtime_15fps(self):
        for tick in range(180):
            cycle,index,due=self.clock.locate(100+tick/15)
            self.assertEqual((cycle,index),(0,tick*2))
            self.assertAlmostEqual(due,100+(tick+1)/15)

    def test_slow_processing_skips_obsolete_frames(self):
        self.assertEqual(self.clock.locate(100)[1],0)
        cycle,index,due=self.clock.locate(100.41)
        self.assertEqual((cycle,index),(0,12))
        self.assertGreater(due,100.41)
        self.assertLessEqual(due-100.41,1/15)

    def test_loop_uses_absolute_timeline_without_accumulated_delay(self):
        for loop in (1,2,10,100):
            cycle,index,due=self.clock.locate(100+loop*12)
            self.assertEqual((cycle,index),(loop,0))
            self.assertAlmostEqual(due,100+loop*12+1/15)
        self.assertEqual(self.clock.locate(124.41)[:2],(2,12))

    def test_source_fps_caps_target(self):
        self.assertEqual(PlaybackClock(5,80,15,0).target_fps,5)

if __name__=='__main__': unittest.main(verbosity=2)
