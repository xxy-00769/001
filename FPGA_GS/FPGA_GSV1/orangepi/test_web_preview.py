"""v0.1.1 HTTP regression only; does not run recognition/UDP regression suites."""
import json
import tempfile
import threading
import time
import unittest
from types import SimpleNamespace
from urllib.error import HTTPError
from urllib.request import urlopen
import cv2
import numpy as np
from main import App

class WebPreview(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.app=App(SimpleNamespace(mode='FILE_TEST',scene=None,output=self.temp.name,web_port=0))
        self.app.preview()
        self.base='http://127.0.0.1:'+str(self.app.server.server_address[1])

    def tearDown(self):
        self.app.stop.set(); self.app.server.shutdown(); self.app.server.server_close()
        self.app.logfile.close(); self.temp.cleanup()

    def check_headers(self,response):
        self.assertIn('no-store',response.headers['Cache-Control'])
        self.assertIn('no-cache',response.headers['Cache-Control'])
        self.assertEqual(response.headers['Pragma'],'no-cache')
        self.assertEqual(response.headers['Expires'],'0')

    def test_first_frame_wait_routes_and_recovery(self):
        for path in ('/latest.jpg','/latest.jpg?t=first','/raw.jpg?t=first','/stream.mjpg?t=first'):
            with self.assertRaises(HTTPError) as raised: urlopen(self.base+path)
            self.assertEqual(raised.exception.code,503)
            self.check_headers(raised.exception)
            raised.exception.close()
        for path in ('/','/?t=page','/status.json','/status.json?t=dynamic'):
            with urlopen(self.base+path) as response:
                self.assertEqual(response.status,200); self.check_headers(response)
                data=response.read()
                if path.startswith('/status'): self.assertEqual(json.loads(data)['processed'],0)
                else: self.assertIn('等待首帧',data.decode())
        jpeg=cv2.imencode('.jpg',np.full((48,64,3),127,np.uint8))[1].tobytes()
        with self.app.lock:
            self.app.jpeg=jpeg; self.app.raw_jpeg=jpeg
            self.app.preview_sequence=1; self.app.preview_meta=(1,42,time.monotonic())
        for path in ('/latest.jpg','/latest.jpg?t=arbitrary-123','/raw.jpg','/raw.jpg?t=raw'):
            with urlopen(self.base+path) as response:
                self.assertEqual(response.status,200); self.check_headers(response)
                self.assertEqual(response.headers['Content-Type'],'image/jpeg')
                self.assertEqual(response.headers['X-Frame-Sequence'],'1')
                self.assertEqual(response.headers['X-Frame-ID'],'42')
                image=cv2.imdecode(np.frombuffer(response.read(),np.uint8),cv2.IMREAD_COLOR)
                self.assertEqual(image.shape,(48,64,3))

    def test_after_wait_releases_publisher_lock(self):
        jpeg=cv2.imencode('.jpg',np.full((48,64,3),127,np.uint8))[1].tobytes()
        with self.app.lock:
            self.app.jpeg=jpeg; self.app.preview_sequence=1
            self.app.preview_meta=(1,42,time.monotonic())
        def publish():
            time.sleep(.06)
            with self.app.preview_ready:
                self.app.preview_sequence=2; self.app.preview_meta=(2,44,time.monotonic())
                self.app.preview_ready.notify_all()
        publisher=threading.Thread(target=publish); publisher.start()
        with urlopen(self.base+'/latest.jpg?t=query&after=1',timeout=2) as response:
            self.assertEqual(response.headers['X-Frame-Sequence'],'2')
            self.assertEqual(response.headers['X-Frame-ID'],'44')
        publisher.join(timeout=1); self.assertFalse(publisher.is_alive())

    def test_stream_query_sends_distinct_publications(self):
        jpeg=cv2.imencode('.jpg',np.full((48,64,3),127,np.uint8))[1].tobytes()
        with self.app.lock:
            self.app.jpeg=jpeg; self.app.preview_sequence=1
            self.app.preview_meta=(1,42,time.monotonic())
        with urlopen(self.base+'/stream.mjpg?t=query',timeout=2) as response:
            self.check_headers(response)
            self.assertTrue(response.headers['Content-Type'].startswith('multipart/x-mixed-replace'))
            def read_frame():
                self.assertEqual(response.readline(),b'--frame\r\n')
                headers={}
                while True:
                    line=response.readline()
                    if line==b'\r\n': break
                    key,value=line.decode().strip().split(': ',1); headers[key]=value
                data=response.read(int(headers['Content-Length']))
                self.assertEqual(response.read(2),b'\r\n')
                self.assertIsNotNone(cv2.imdecode(np.frombuffer(data,np.uint8),cv2.IMREAD_COLOR))
                return headers
            self.assertEqual(read_frame()['X-Frame-Sequence'],'1')
            with self.app.preview_ready:
                self.app.preview_sequence=2; self.app.preview_meta=(2,44,time.monotonic())
                self.app.preview_ready.notify_all()
            self.assertEqual(read_frame()['X-Frame-ID'],'44')

if __name__=='__main__': unittest.main(verbosity=2)
