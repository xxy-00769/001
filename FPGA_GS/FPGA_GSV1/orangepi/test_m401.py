"""Synthetic fixtures verify rules/transport only, never real-world accuracy."""
import dataclasses
import socket
import threading
import time
import unittest
import cv2
import numpy as np
from link import Link
from vendor.protocol import *
from vision import Vision,decide

def observation(light='GREEN',left='DASHED',right='SOLID',actions=(1,2,3)):
    return dict(signal=dict(state=light,actions=actions,confidence=.9),
                lanes=dict(left=dict(state=left,confidence=.9),right=dict(state=right,confidence=.9)))

class Rules(unittest.TestCase):
    def test_rules(self):
        self.assertEqual(decide(observation('RED'),3)['reason'],1)
        self.assertEqual(decide(observation('RED'),4)['code'],1)
        self.assertEqual(decide(observation(),1)['code'],1)
        self.assertEqual(decide(observation(),2)['reason'],2)
        self.assertEqual(decide(observation(),3)['code'],1)
        self.assertEqual(decide(observation(left='SOLID',right='DASHED'),1)['reason'],2)
        self.assertEqual(decide(observation(left='SOLID',right='DASHED'),2)['code'],1)
        self.assertEqual(decide(observation('UNKNOWN',left='UNKNOWN',right='UNKNOWN'),1)['code'],0)
        self.assertEqual(decide(observation(actions=()),3)['code'],0)
        self.assertEqual(decide(observation(actions=()),2)['code'],0)
        low=observation(); low['signal']['confidence']=.2
        self.assertEqual(decide(low,3)['code'],0)
        self.assertEqual(decide(observation(left='UNKNOWN',right='UNKNOWN'),3)['code'],1)

    def test_visual_candidates_and_ambiguity(self):
        vision=Vision()
        for state,color in [('RED',(0,0,255)),('GREEN',(0,255,0))]:
            image=np.full((720,1280,3),160,np.uint8)
            cv2.rectangle(image,(600,80),(640,220),(20,20,20),-1)
            cv2.circle(image,(620,110),10,color,-1)
            result,_=vision.analyze(image)
            self.assertEqual(result['signal']['state'],state)
            self.assertEqual(result['decisions']['3']['code'],0) # no lane association
        blank=np.full((720,1280,3),160,np.uint8)
        self.assertEqual(vision.analyze(blank)[0]['signal']['state'],'UNKNOWN')
        cv2.rectangle(blank,(200,100),(600,300),(0,0,255),-1)
        self.assertEqual(vision.analyze(blank)[0]['signal']['state'],'UNKNOWN')

    def test_lane_continuity_fixture(self):
        config=dict(lane_geometry_confirmed=True,road_quad=[[0,0],[1,0],[1,1],[0,1]])
        image=np.full((240,320,3),40,np.uint8)
        cv2.line(image,(65,0),(65,239),(230,230,230),5)
        for y in (0,60,120,180): cv2.line(image,(255,y),(255,y+27),(230,230,230),5)
        result,_=Vision(config).analyze(image)
        self.assertEqual(result['lanes']['left']['state'],'SOLID')
        self.assertEqual(result['lanes']['right']['state'],'DASHED')

class Transport(unittest.TestCase):
    def setUp(self):
        self.peer=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        self.peer.bind(('127.0.0.1',0)); self.peer.settimeout(1)
        self.frames=[]; self.history={}; self.logs=[]
        self.link=Link(('127.0.0.1',0),self.peer.getsockname(),
            lambda *x:self.frames.append(x),lambda fid,now:self.history.get(fid),
            lambda kind,**kw:self.logs.append((kind,kw)))

    def tearDown(self):
        self.link.stop.set(); self.link.sock.close(); self.peer.close()

    def get(self): return Message.decode(self.peer.recvfrom(2048)[0])

    def event(self,event=1,frame=42,ttl=2000,code=3):
        return Message(EVENT,self.link.session,event=event,frame=frame,ttl=ttl,code=code)

    def test_exact_frame_wait_ack_retry_and_stale(self):
        now=time.monotonic()
        self.link.receive(self.event(),now)
        self.assertEqual(self.get().kind,EVENT_ACK)
        self.history[43]=observation('RED')
        self.link.tick(now+.1)
        self.assertEqual(self.link.stats['results'],0)
        self.history[42]=observation()
        self.link.tick(now+.2); result=self.get()
        self.assertEqual((result.kind,result.frame,result.event,result.code),(RESULT,42,1,1))
        self.link.tick(now+.41); self.assertEqual(self.get(),result)
        self.link.receive(Message(RESULT_ACK,self.link.session,event=1,sequence=result.sequence,code=1),now+.42)
        self.assertIsNone(self.link.retry)
        self.link.receive(self.event(),now+.5); self.get()
        self.assertIsNone(self.link.pending)
        self.link.receive(self.event(2,44,300),now+.6); self.get()
        self.link.tick(now+.91); expired=self.get()
        self.assertEqual((expired.frame,expired.code,expired.ttl),(44,0,300))
        self.link.receive(self.event(3,45),now+1); self.get()
        self.link.receive(self.event(2,44),now+1.1); self.get()
        self.assertEqual(self.link.pending[0].event,3)

    def test_drop_whole_frame_and_recover(self):
        self.assertEqual(HEADER.size,48)
        payload=b'\x00\xf8'*(PAYLOAD//2)
        def fragment(frame,i):
            return Message.decode(Message(FRONT_RAW,self.link.session,frame=frame,index=i,
                offset=i*PAYLOAD,count=FRAGMENTS,payload=payload).encode())
        now=time.monotonic()
        for i in range(FRAGMENTS):
            if i!=10: self.link.receive(fragment(1,i),now)
        self.assertEqual(len(self.frames),0)
        for i in range(FRAGMENTS): self.link.receive(fragment(2,i),now+.1)
        self.assertEqual(len(self.frames),1)
        self.assertEqual(self.frames[0][0],2)
        self.assertEqual(len(self.frames[0][1]),FRAME_BYTES)
        self.assertEqual(self.link.assembler.dropped,1)
        self.link.receive(fragment(1,10),now+.2)
        self.assertEqual(len(self.frames),1)
        self.link.receive(dataclasses.replace(self.event(),session=self.link.session+1),now+.3)
        self.assertIsNone(self.link.pending)

    def test_real_udp_heartbeat_ack_independent_of_inference(self):
        worker=threading.Thread(target=self.link.run,daemon=True); worker.start()
        target=self.link.sock.getsockname(); now=time.monotonic()
        self.peer.sendto(self.event().encode(),target)
        kinds=set(); ack_ms=None
        while time.monotonic()-now<.6:
            msg=self.get(); kinds.add(msg.kind)
            if msg.kind==EVENT_ACK and ack_ms is None: ack_ms=(time.monotonic()-now)*1000
        self.assertTrue({HELLO,HEARTBEAT,EVENT_ACK} <= kinds)
        self.assertLess(ack_ms,100)
        self.link.stop.set(); worker.join(1)
        print('SIMULATION UDP ACK ms:',round(ack_ms,3))

if __name__=='__main__': unittest.main(verbosity=2)
