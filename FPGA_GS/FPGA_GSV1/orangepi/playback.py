"""Constant-frame-rate file clock: select current media frame, never queue old work."""
import math

class PlaybackClock:
    def __init__(self,source_fps,frame_count,target_fps,start):
        if source_fps<=0 or frame_count<1 or target_fps<=0: raise ValueError('Invalid playback profile')
        self.source_fps=source_fps; self.frame_count=frame_count
        self.target_fps=min(source_fps,target_fps)
        self.duration=frame_count/source_fps; self.start=start

    def locate(self,now):
        elapsed=max(0,now-self.start)
        cycle=int(math.floor(elapsed/self.duration))
        within=elapsed-cycle*self.duration
        source_index=min(self.frame_count-1,int(math.floor(within*self.source_fps+1e-7)))
        tick=int(math.floor(within*self.target_fps+1e-7))
        next_due=self.start+cycle*self.duration+(tick+1)/self.target_fps
        next_due=min(next_due,self.start+(cycle+1)*self.duration)
        return cycle,source_index,next_due
