"""Generated local fixture + 60s duplex software loopback, never board FPS."""
import argparse,dataclasses,hashlib,json,queue,socket,subprocess,threading,time
from pathlib import Path
from types import SimpleNamespace
from console import Bench
from protocol import *
from video_source import VideoSource,find_ffmpeg
from PIL import Image

def wait(predicate,timeout=5):
    end=time.monotonic()+timeout
    while not predicate():
        assert time.monotonic()<end,'timeout'
        time.sleep(.01)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--fps',type=float,default=5);ap.add_argument('--seconds',type=float,default=60);a=ap.parse_args()
    R=Path(__file__).resolve().parents[2];O=R/'reports'/('host_m31_'+time.strftime('%Y%m%d_%H%M%S'));O.mkdir()
    exe=find_ffmpeg();fixture=O/'generated_fixture.mp4'
    subprocess.run([exe,'-y','-hide_banner','-loglevel','error','-f','lavfi','-i',
       'testsrc2=size=640x360:rate=30','-t','2','-c:v','mpeg4','-q:v','4',str(fixture)],check=True)
    # File lifecycle: actual decode, native time, pause, loop, EOF, replacement.
    source=VideoSource(5,exe);source.select(fixture,False);wait(lambda:source.frames>=2)
    source.toggle();time.sleep(.3);paused=source.frames;time.sleep(.3);assert source.frames==paused
    source.toggle();wait(lambda:source.state=='eof',4);assert source.frames==10
    source.select(fixture,True);wait(lambda:source.frames>=12,4);assert source.state=='playing'
    source.select();assert source.state=='pattern' and source.latest is None;source.close()
    peer=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);peer.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,4*1024*1024)
    peer.bind(('127.0.0.2',PORT));peer.settimeout(.05)
    bench=Bench(SimpleNamespace(bind='127.0.0.1',board='127.0.0.2',right_fps=a.fps,front_fps=5,
       drop_every=0,auto='allow',stats=None,video=str(fixture),ffmpeg=exe,loop=True))
    stop=threading.Event();errors=[];counter={'complete':0,'incomplete':0,'packets':0,'control_ack':0,'control_result':0}
    frame=None;expected=0;received=0;latest_key=0
    target=('127.0.0.1',PORT)
    def receiver():
        nonlocal frame,expected,received
        while not stop.is_set():
            try: data,_=peer.recvfrom(2048)
            except socket.timeout: continue
            try:
                msg=Message.decode(data)
                if msg.kind==VIDEO_IN:
                    if frame!=msg.frame:
                        if frame is not None and received!=FRAGMENTS:counter['incomplete']+=1
                        frame=msg.frame;received=0;expected=0
                    assert msg.index==expected and msg.offset==expected*PAYLOAD
                    assert len(msg.payload)==PAYLOAD
                    expected+=1;received+=1;counter['packets']+=1
                    if received==FRAGMENTS:counter['complete']+=1
                elif msg.kind==EVENT_ACK:counter['control_ack']+=1
                elif msg.kind==RESULT:
                    counter['control_result']+=1
                    peer.sendto(Message(RESULT_ACK,bench.session,event=msg.event,sequence=msg.sequence,code=1).encode(),target)
            except Exception as exc:errors.append(str(exc))
    def front_sender():
        nonlocal latest_key
        # Independent byte oracle; covers original PNG and byte order.
        raw=b'\x00\xf8\xe0\x07\x1f\x00'*(WIDTH*HEIGHT//3)
        fid=0;due=time.monotonic();heartbeat=0
        while not stop.is_set():
            for i in range(FRAGMENTS):
                peer.sendto(Message(FRONT_RAW,bench.session,frame=fid,index=i,offset=i*PAYLOAD,count=FRAGMENTS,
                    payload=raw[i*PAYLOAD:(i+1)*PAYLOAD]).encode(),target)
            if fid%3==0:
                peer.sendto(Message(HEARTBEAT,bench.session,flags=1,frame=counter['complete'],offset=counter['incomplete']).encode(),target)
            if fid%5==0:
                latest_key+=1;peer.sendto(Message(EVENT,bench.session,event=latest_key,frame=fid,code=latest_key%4+1).encode(),target)
            fid+=1;due+=.2
            if stop.wait(max(0,due-time.monotonic())):break
    threads=[threading.Thread(target=receiver),threading.Thread(target=front_sender)]
    for t in threads:t.start()
    start=time.monotonic();time.sleep(a.seconds);elapsed=time.monotonic()-start
    stop.set()
    for t in threads:t.join(timeout=3)
    snapshot=bench.snapshot()
    if bench.latest_image:
        image=Image.frombytes('RGB',(WIDTH,HEIGHT),bench.latest_image[1],'raw','BGR;16')
        png=O/'front_original_1280x720.png';image.save(png)
        saved=Image.open(png);assert saved.size==(1280,720)
        assert [saved.getpixel((i,0)) for i in range(3)]==[(255,0,0),(0,255,0),(0,0,255)]
    bench.close();peer.close()
    assert not errors,errors
    assert snapshot['front_frames']>0 and counter['complete']>0 and counter['control_result']>0
    report=dict(SoftwareLoopbackOnly=True,BoardMeasured=False,Seconds=elapsed,RequestedRightFps=a.fps,
       ActualRightCompleteFps=counter['complete']/elapsed,ActualFrontReceiveFps=snapshot['front_frames']/elapsed,
       RightReceive=counter,Stats=snapshot,FileLifecyclePass=True,OriginalPNGPass=True,
       FFmpeg=exe,GeneratedFixture=str(fixture),Verdict='PASS')
    (O/'result.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
    print(O);print(json.dumps(report,indent=2,ensure_ascii=False))
if __name__=='__main__':main()
