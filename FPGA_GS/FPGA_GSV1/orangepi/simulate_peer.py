"""Loopback GSV3 integration fixture. Starts a SIMULATION app, never a real FPGA."""
import json
import socket
import subprocess
import sys
import time
from pathlib import Path
import cv2
import numpy as np
from vendor.protocol import *

def free_port(udp=False):
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM if udp else socket.SOCK_STREAM) as sock:
        sock.bind(('127.0.0.1',0)); return sock.getsockname()[1]

def main():
    out=Path(sys.argv[1] if len(sys.argv)>1 else 'runs/simulation')
    out.mkdir(parents=True,exist_ok=True)
    scene=out/'scene.json'
    scene.write_text(json.dumps(dict(configuration_kind='SIMULATION_SCENE_CONFIGURATION',
        signal_actions=[1,2,3],lane_geometry_confirmed=False)),encoding='utf-8')
    peer=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    peer.bind(('127.0.0.1',0)); peer.settimeout(2)
    port=free_port(True); target=('127.0.0.1',port)
    console=(out/'console.jsonl').open('w',encoding='utf-8')
    process=subprocess.Popen([sys.executable,'main.py','--mode','SIMULATION','--bind','127.0.0.1',
        '--peer','127.0.0.1','--port',str(port),'--peer-port',str(peer.getsockname()[1]),
        '--scene',str(scene),'--output',str(out/'app'),'--web-port',str(free_port()),'--duration','6','--snapshot-every','1'],
        stdout=console,stderr=subprocess.STDOUT)
    latencies=[]; results=[]
    try:
        msg=Message.decode(peer.recvfrom(2048)[0]); sid=msg.session
        peer.sendto(Message(WELCOME,sid).encode(),target)
        for event,color,expected in [(1,(0,0,255),2),(2,(0,255,0),1)]:
            frame=100+event
            image=np.full((720,1280,3),160,np.uint8)
            cv2.rectangle(image,(600,80),(640,220),(20,20,20),-1)
            cv2.circle(image,(620,110),10,color,-1)
            b,g,r=[image[:,:,i].astype(np.uint16) for i in range(3)]
            raw=(((r>>3)<<11)|((g>>2)<<5)|(b>>3)).astype('<u2').tobytes()
            sent=time.perf_counter()
            peer.sendto(Message(EVENT,sid,event=event,frame=frame,code=3).encode(),target)
            while True:
                reply=Message.decode(peer.recvfrom(2048)[0])
                if reply.kind==EVENT_ACK:
                    latencies.append((time.perf_counter()-sent)*1000); break
            # Event precedes image. Pace test datagrams to avoid artificial burst overflow.
            for i in range(FRAGMENTS):
                peer.sendto(Message(FRONT_RAW,sid,frame=frame,index=i,offset=i*PAYLOAD,
                    count=FRAGMENTS,payload=raw[i*PAYLOAD:(i+1)*PAYLOAD]).encode(),target)
                if i%8==0: time.sleep(.002)
            while True:
                reply=Message.decode(peer.recvfrom(2048)[0])
                if reply.kind==RESULT:
                    assert (reply.session,reply.event,reply.frame,reply.code)==(sid,event,frame,expected),reply
                    results.append(dict(event=reply.event,frame=reply.frame,code=reply.code,reason=reply.reason))
                    peer.sendto(Message(RESULT_ACK,sid,event=reply.event,sequence=reply.sequence,code=1).encode(),target)
                    break
        process.wait(timeout=9)
        assert process.returncode==0,process.returncode
        summary=json.loads((out/'app/summary.json').read_text(encoding='utf-8'))
        assert (out/'app/raw_00000101.rgb565').stat().st_size==FRAME_BYTES
        assert summary['link']['result_accepted']==2,summary['link']
        assert summary['link']['disconnects']>=1,summary['link']
        report=dict(mode='SIMULATION',hardware_validation=False,results=results,
            ack_ms=latencies,link=summary['link'],inference_mean_ms=summary['inference_mean_ms'])
        (out/'report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        print(json.dumps(report,ensure_ascii=False))
    finally:
        if process.poll() is None: process.terminate(); process.wait(timeout=5)
        peer.close(); console.close()

if __name__=='__main__': main()
