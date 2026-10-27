"""Targeted reboot regression with in-memory packets only; no business UDP transmission."""
import collections
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import time
import types
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from link import Link
from feedback import EventFeedback
from vendor.protocol import Message, Assembler, FRONT_RAW, WELCOME, EVENT, RESULT_ACK, FRAGMENTS, PAYLOAD


def frame(link, fid, now):
    for i in range(FRAGMENTS):
        link.receive(Message(FRONT_RAW,link.session,frame=fid,index=i,count=FRAGMENTS,
                             offset=i*PAYLOAD,payload=bytes(PAYLOAD)),now)


class ReconnectChecks(unittest.TestCase):
    def setUp(self):
        self.sent=[];self.published=[];self.resets=[]
        with patch('link.socket.socket'):
            self.link=Link(('127.0.0.1',0),('127.0.0.1',1),
                lambda *a:self.published.append(a),lambda *a:None,lambda *a,**kw:None,
                reset_live=lambda *a:self.resets.append(a))
        self.link.send=lambda m:self.sent.append(m) or True
        self.link.feedback.send=self.link.send
        self.now=time.monotonic()

    def test_timeout_clears_epoch_then_recovers_lower_frame(self):
        l=self.link;old=l.session;l.receive(Message(WELCOME,old),self.now)
        frame(l,74448,self.now+.01)
        l.feedback.configure('SELF_TEST','allow',self.now+.1)
        l.receive(Message(EVENT,old,event=11,frame=74448,code=1),self.now+.1)
        l.tick(self.now+.1);self.assertIsNotNone(l.feedback.retry)
        l.tick(self.now+2.11)
        self.assertNotEqual(l.session,old);self.assertEqual(len(self.resets),1)
        self.assertIsNone(l.assembler.frame);self.assertIsNone(l.feedback.retry)
        self.assertFalse(l.feedback.records);self.assertIsNone(l.feedback.latest_event)
        self.assertEqual(l.feedback.mode,'REAL')
        l.hello(self.now+4.9);self.assertEqual(l.stats['heartbeat_tx'],0)
        l.receive(Message(WELCOME,old),self.now+5.12)
        self.assertFalse(l.online)
        l.hello(self.now+5.12);l.receive(Message(WELCOME,l.session),self.now+5.13)
        frame(l,7838,self.now+5.14)
        self.assertEqual([x[0] for x in self.published],[74448,7838])
        l.receive(Message(EVENT,l.session,event=1,frame=7838,code=4),self.now+5.15)
        self.assertEqual(l.feedback.latest_event,1)

    def test_no_repeated_rotation_and_fixed_handshake_request(self):
        l=self.link;l.receive(Message(WELCOME,l.session),self.now);l.tick(self.now+2.01)
        session=l.session
        for i in range(10):
            l.tick(self.now+3+i);l.hello(self.now+3+i)
        self.assertEqual(l.session,session);self.assertEqual(l.reconnects,1)
        self.assertTrue(self.sent);self.assertEqual({m.session for m in self.sent},{session})
        self.assertEqual({m.reason for m in self.sent if m.kind==1},{15})

    def test_quiet_drops_inbound_even_old_periodic_traffic(self):
        l=self.link;l.receive(Message(WELCOME,l.session),self.now);l.tick(self.now+2.01)
        session=l.session
        for t in (2.1,3.,4.9):l.receive(Message(WELCOME,session),self.now+t)
        self.assertFalse(l.online);self.assertFalse(l.ever_received)
        self.assertEqual(l.reconnects,1)

    def test_welcome_and_single_late_packet_do_not_reset(self):
        l=self.link;l.receive(Message(WELCOME,l.session),self.now)
        frame(l,74448,self.now+.01)
        retained=l.assembler
        for i in range(10):l.receive(Message(WELCOME,l.session),self.now+.02+i*.1)
        l.receive(Message(FRONT_RAW,l.session,frame=7838,index=0,count=FRAGMENTS,payload=bytes(PAYLOAD)),self.now+3)
        l.tick(self.now+3.01)
        self.assertIs(l.assembler,retained);self.assertEqual(l.reconnects,0)
        frame(l,74450,self.now+3.02);self.assertEqual(self.published[-1][0],74450)

    def test_sustained_regression_recovers_if_outage_was_not_observed(self):
        l=self.link;frame(l,74448,self.now)
        for fid,delta in ((7838,.1),(7840,1.1),(7842,2.2)):
            l.receive(Message(FRONT_RAW,l.session,frame=fid,index=0,count=FRAGMENTS,payload=bytes(PAYLOAD)),self.now+delta)
        self.assertEqual(l.reconnect_reason,'SUSTAINED_FRAME_REGRESSION')
        self.assertEqual(l.reconnects,1)
        l.receive(Message(WELCOME,l.session),self.now+5.3);frame(l,7850,self.now+5.4)
        self.assertEqual(self.published[-1][0],7850)

    def test_normal_wrap_order_and_duplicate_guards_retained(self):
        l=self.link;frame(l,0xfffffffe,self.now);frame(l,1,self.now+.1)
        frame(l,1,self.now+.2);frame(l,0xfffffffe,self.now+.3)
        self.assertEqual([x[0] for x in self.published],[0xfffffffe,1])
        self.assertEqual(l.reconnects,0)

    def test_reset_prevents_old_ack_old_inference_and_event_collision(self):
        l=self.link;l.receive(Message(WELCOME,l.session),self.now);old=l.session
        l.feedback.configure('SELF_TEST','allow',self.now)
        l.receive(Message(EVENT,old,event=1,frame=20,code=1),self.now);l.tick(self.now)
        l.reconnect(self.now+.1,'TEST_CONFIRMED_OUTAGE')
        new=l.session;l.receive(Message(WELCOME,new),self.now+3.2)
        l.receive(Message(EVENT,new,event=1,frame=20,code=1),self.now+3.21)
        l.receive(Message(RESULT_ACK,old,event=1,sequence=1,code=1),self.now+3.22)
        l.feedback.inference_completed(20,self.now+3.22,session=old)
        self.assertIsNone(l.feedback.records[-1]['result_ack'])
        self.assertFalse(l.feedback.records[-1]['inference_complete'])

    def test_app_cache_clear_and_inflight_old_processing_cannot_republish(self):
        from main import App
        import numpy as np
        with tempfile.TemporaryDirectory() as folder:
            app=App(types.SimpleNamespace(output=folder,scene=None,mode='LIVE_FRONT',preview_width=640,preview_quality=70,snapshot_every=25))
            app.latest_result={'frame_id':74448};app.history[74448]=(self.now,{})
            app.received_frames[74448]=self.now;app.jpeg=app.raw_jpeg=b'old'
            app.latest=(74448,b'old',self.now,0);app.latest_pending=True
            app.reset_live(1,123,self.now,'PEER_TIMEOUT')
            self.assertFalse(app.history or app.received_frames or app.latest_result)
            self.assertIsNone(app.jpeg);self.assertIsNone(app.latest)
            app.vision.analyze=lambda image: (app.reset_live(2,456,self.now+.1,'TEST') or
                (dict(signal=dict(state='UNKNOWN',association='UNASSIGNED'),lanes=dict(left=dict(state='UNKNOWN'),right=dict(state='UNKNOWN')),inference_ms=0,decisions={}),image.copy()))
            app.process(7838,np.zeros((720,1280,3),np.uint8),self.now,generation=1)
            self.assertFalse(app.history or app.latest_result);self.assertIsNone(app.jpeg)
            app.logfile.close()


if __name__=='__main__':unittest.main(verbosity=2)
