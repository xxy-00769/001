"""Targeted config/latest-slot checks; no video, network traffic, or inference."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import socket
import threading
import unittest
from unittest.mock import patch
from link import Link
from main import App
from vendor.protocol import HELLO


class ConfigChecks(unittest.TestCase):
    def test_periodic_hellos_keep_request(self):
        for fps in (0,5,15,30):
            sent=[]
            with patch('link.socket.socket') as factory:
                link=Link(('127.0.0.1',0),('127.0.0.1',1),lambda *a:None,lambda *a:None,lambda *a,**kw:None,front_fps=fps)
                def timeout(*args):
                    if sum(x.kind==HELLO for x in sent)>=3:link.stop.set()
                    raise socket.timeout()
                factory.return_value.recvfrom.side_effect=timeout
                link.send=sent.append
                clock=iter(i*.3 for i in range(30))
                with patch('link.time.monotonic',side_effect=lambda:next(clock)):
                    link.run()
            requests=[x.reason for x in sent if x.kind==HELLO]
            self.assertGreaterEqual(len(requests),3)
            self.assertEqual(set(requests),{fps})

    def test_pending_overwrite_is_app_skip_only(self):
        app=App.__new__(App);app.lock=threading.Lock();app.latest_pending=False
        import collections
        app.received_frames=collections.OrderedDict()
        app.live_epoch=0
        app.skipped_complete_frames=0;app.latest=None
        app.publish(10,b'first',1.)
        self.assertEqual(app.skipped_complete_frames,0)
        app.publish(12,b'latest',2.)
        self.assertEqual(app.skipped_complete_frames,1)
        self.assertEqual(app.latest,(12,b'latest',2.,0))
        app.latest_pending=False  # A consumer takes the single pending slot.
        app.publish(14,b'next',3.)
        self.assertEqual(app.skipped_complete_frames,1)


if __name__=='__main__':unittest.main(verbosity=2)
