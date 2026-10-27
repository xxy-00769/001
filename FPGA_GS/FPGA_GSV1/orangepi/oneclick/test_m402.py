"""Only M4-02 event/control checks. Fake send sink; never sends FPGA UDP traffic."""
import collections
import json
from pathlib import Path
import sys
import tempfile
import time
import types
import unittest
import urllib.request
import urllib.error
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from feedback import EventFeedback
from vendor.protocol import Message, EVENT, EVENT_ACK, RESULT, RESULT_ACK


class FeedbackChecks(unittest.TestCase):
    def setUp(self):
        self.now = time.monotonic()
        self.sent = []
        self.observations = {}
        self.states = {}
        self.stats = collections.Counter()
        self.f = EventFeedback(7, self.send, lambda fid, now: self.observations.get(fid),
                               lambda fid, now: self.states.get(fid, {}), lambda *a, **k: None, self.stats)

    def send(self, msg):
        self.sent.append(msg)
        return True

    def event(self, event=1, frame=100, ttl=2000, action=1):
        msg = Message(EVENT, 7, event=event, frame=frame, code=action, ttl=ttl)
        self.f.event(msg, self.now)
        return msg

    def self_test(self, selection='allow'):
        self.f.configure('SELF_TEST', selection, self.now)

    def results(self):
        return [m for m in self.sent if m.kind == RESULT]

    def test_duplicate_ack_but_one_event_and_unchanged_deadline(self):
        self.self_test();msg=self.event();self.f.tick(self.now)
        deadline=self.f.records[-1]['host_deadline_monotonic']
        self.f.event(msg,self.now+.15)
        self.assertEqual(len([m for m in self.sent if m.kind==EVENT_ACK]),2)
        self.assertEqual(len(self.results()),1)
        self.assertEqual(self.stats['events'],1)
        self.assertEqual(self.f.records[-1]['host_deadline_monotonic'],deadline)

    def test_new_event_cancels_old_wait_and_retry(self):
        self.event();self.event(2,101)
        self.assertEqual(self.f.records[0]['cancel_reason'],'NEW_EVENT')
        self.self_test();self.event(3,102);self.f.tick(self.now)
        self.event(4,103);self.f.tick(self.now+.21)
        self.assertEqual([(m.event,m.frame,m.sequence) for m in self.results()],[(3,102,1),(4,103,1)])

    def test_ttl_no_send_at_expiry_and_no_retry_extension(self):
        self.event(ttl=100);self.f.tick(self.now+.001)
        self.assertFalse(self.results())
        self.self_test();msg=self.event(2,ttl=1000);self.f.tick(self.now)
        self.f.event(msg,self.now+.85);self.f.tick(self.now+.91)
        self.assertEqual(len(self.results()),1)
        self.assertEqual(self.results()[0].ttl,1000)
        self.assertIsNone(self.f.retry)

    def test_retry_same_identity_sequence_and_ttl(self):
        self.self_test();self.event();self.f.tick(self.now);self.f.tick(self.now+.21)
        self.assertEqual(self.results()[0],self.results()[1])
        self.assertEqual(self.f.records[-1]['result']['attempts'],2)

    def test_ack_session_event_sequence_ignores_ack_frame(self):
        self.self_test();self.event();self.f.tick(self.now)
        for kwargs in [dict(session=8,event=1,sequence=1),dict(session=7,event=2,sequence=1),dict(session=7,event=1,sequence=2)]:
            self.f.ack(Message(RESULT_ACK,**kwargs,code=1),self.now+.1)
            self.assertIsNone(self.f.records[-1]['result_ack'])
        self.f.ack(Message(RESULT_ACK,7,event=1,sequence=1,frame=999,code=1),self.now+.12)
        self.f.ack(Message(RESULT_ACK,7,event=1,sequence=1,code=0),self.now+.14)
        ack=self.f.records[-1]['result_ack']
        self.assertTrue(ack['accepted']);self.assertAlmostEqual(ack['event_to_ack_ms'],120,places=2)
        self.assertIsNone(self.f.retry)

    def test_old_ack_does_not_cancel_new_retry(self):
        self.self_test();self.event();self.f.tick(self.now)
        self.event(2,101);self.f.tick(self.now+.01)
        self.f.ack(Message(RESULT_ACK,7,event=1,sequence=1,code=1),self.now+.03)
        self.assertEqual(self.f.retry[0].event,2)

    def test_simulation_requires_new_real_event_and_never_calls_decide(self):
        self.self_test('red');self.f.tick(self.now)
        self.assertFalse(self.sent)
        self.event(frame=123)
        with patch('feedback.decide',side_effect=AssertionError('simulation called vision')):
            self.f.tick(self.now)
        self.assertEqual((self.results()[0].session,self.results()[0].event,self.results()[0].frame),(7,1,123))
        self.assertEqual((self.results()[0].code,self.results()[0].reason),(2,1))
        self.assertTrue(self.f.records[-1]['result']['simulated'])

    def test_each_self_test_choice_maps_existing_codes(self):
        for i,(choice,expected) in enumerate([('allow',(1,0)),('deny',(2,0)),('red',(2,1)),('solid',(2,2)),('unknown',(0,0))],1):
            self.self_test(choice);self.event(i);self.f.tick(self.now)
            result=self.results()[-1];self.assertEqual((result.code,result.reason),expected)

    def test_mode_change_cancels_old_and_restores_real_exact_lookup(self):
        self.self_test();old=self.event();self.f.tick(self.now)
        self.f.configure('REAL','allow',self.now+.05)
        self.f.event(old,self.now+.1);self.f.tick(self.now+.3)
        self.assertEqual(len(self.results()),1)
        self.now+=.4;self.event(2,200);self.f.tick(self.now+.81)
        self.assertEqual((self.results()[-1].code,self.results()[-1].frame),(0,200))
        self.assertFalse(self.f.records[-1]['simulated'])

    def test_missing_frame_and_received_without_inference_differ(self):
        self.event();self.f.tick(self.now+.81)
        self.assertEqual(self.f.records[-1]['result']['explanation'],'EVENT_FRAME_NOT_RECEIVED')
        self.states[101]=dict(received=True,received_monotonic=self.now)
        self.event(2,101);self.f.tick(self.now+.82)
        self.assertEqual(self.f.records[-1]['result']['explanation'],'EVENT_FRAME_INFERENCE_UNAVAILABLE')

    def test_delayed_exact_frame_only_and_real_unknown_reason(self):
        self.event(frame=100)
        observation=dict(signal=dict(state='UNKNOWN',actions=[],confidence=0,association='UNASSIGNED'),lanes={})
        self.observations[101]=observation;self.f.tick(self.now+.1)
        self.assertFalse(self.results())
        self.states[100]=dict(received=True,received_monotonic=self.now+.2,inference_complete=True)
        self.observations[100]=observation
        self.f.frame_received(100,self.now+.2,self.now+.2);self.f.tick(self.now+.21)
        self.assertEqual(self.results()[-1].frame,100)
        self.assertEqual(self.f.records[-1]['result']['explanation'],'SIGNAL_STATE_OR_ASSOCIATION_UNCERTAIN')
        self.assertEqual(self.f.counts['exact_frame_received'],1)

    def test_snapshot_is_bounded_copy_and_event_id_wrap(self):
        for i in range(40):self.event(i+1,100+i)
        snapshot=self.f.snapshot(self.now+3)
        self.assertEqual(len(snapshot['recent_events']),32)
        self.assertEqual(snapshot['counts']['events'],40)
        snapshot['recent_events'][-1]['event_ack']['sent']=False
        self.assertTrue(self.f.records[-1]['event_ack']['sent'])
        self.f.latest_event=0xffffffff;self.event(0,999)
        self.assertEqual(self.f.latest_event,0)


class ControlHTTPChecks(unittest.TestCase):
    def test_token_query_mode_isolation_and_no_event_injection(self):
        from main import App
        with tempfile.TemporaryDirectory() as folder:
            app=App(types.SimpleNamespace(mode='LIVE_FRONT',scene=None,output=folder,web_port=0,front_fps=15,sample_fps=15))
            sent=[]
            feedback=EventFeedback(7,lambda m:sent.append(m),lambda *a:None,lambda *a:{},lambda *a,**kw:None,collections.Counter())
            app.link=types.SimpleNamespace(feedback=feedback,snapshot=lambda:dict(feedback=feedback.snapshot(time.monotonic())))
            app.preview();url='http://127.0.0.1:'+str(app.server.server_port)
            def post(token,mode='SELF_TEST'):
                return urllib.request.urlopen(urllib.request.Request(url+'/feedback/control?t=1',
                    data=json.dumps(dict(mode=mode,selection='red')).encode(),
                    headers={'Content-Type':'application/json','X-M4-Control-Token':token}),timeout=3)
            try:
                with self.assertRaises(urllib.error.HTTPError) as denied:post('bad')
                self.assertEqual(denied.exception.code,403)
                with post(app.control_token) as reply:self.assertTrue(json.load(reply)['ok'])
                self.assertFalse(sent);self.assertFalse(feedback.records)
                app.args.mode='FILE_TEST'
                with self.assertRaises(urllib.error.HTTPError) as isolated:post(app.control_token)
                self.assertEqual(isolated.exception.code,409)
            finally:
                app.stop.set();app.server.shutdown();app.server.server_close();app.logfile.close()


if __name__=='__main__':unittest.main(verbosity=2)
