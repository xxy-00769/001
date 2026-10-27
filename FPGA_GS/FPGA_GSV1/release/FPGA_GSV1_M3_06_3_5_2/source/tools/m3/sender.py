"""A single bounded TX worker, isolated from the receive thread's Python GIL.
Sub-millisecond spin pacing is local to this process (one CPU core while TX).
No bursts to catch up, no change of NIC or machine timer settings.
"""
import queue, struct, time
from protocol import HEADER, MAGIC, VERSION, WIDTH, HEIGHT, PAYLOAD, FRAGMENTS, VIDEO_IN

def send_worker(sock, peer, session, fps, drop_every, jobs, results, stop):
    packet=bytearray(HEADER.size+PAYLOAD); view=memoryview(packet)
    interval=1/fps/FRAGMENTS
    while not stop.is_set():
        try: fid, stamp, pixels, submitted = jobs.get(timeout=.1)
        except queue.Empty: continue
        began=time.perf_counter(); due=began; failures=0; dropped=0; send_time=0.;wait_time=0.;gaps=[];last_sent=None
        source=memoryview(pixels)
        for i in range(FRAGMENTS):
            if stop.is_set(): break
            HEADER.pack_into(packet,0,MAGIC,VERSION,VIDEO_IN,3,1,session,fid,stamp,
                WIDTH,HEIGHT,i*PAYLOAD,PAYLOAD,i,FRAGMENTS,0,0,0,2000,0,0)
            view[HEADER.size:]=source[i*PAYLOAD:(i+1)*PAYLOAD]
            wait_start=time.perf_counter()
            while time.perf_counter()<due: pass
            now=time.perf_counter();wait_time+=now-wait_start
            if last_sent is not None: gaps.append((now-last_sent)*1e6)
            last_sent=now
            if drop_every and i%drop_every==drop_every-1: dropped+=1
            else:
                try: sock.sendto(packet,peer)
                except OSError: failures+=1
            after=time.perf_counter();send_time+=after-now
            # Space send starts; sending/header work fits inside the interval.
            # Late scheduling resets the deadline without a catch-up burst.
            due=now+interval
        else:
            results.put(dict(frame=fid,completed=not failures and not dropped,
                packets=FRAGMENTS-dropped-failures,dropped=dropped,errors=failures,
                gap_min_us=min(gaps),gap_max_us=max(gaps),gap_p99_us=sorted(gaps)[int(len(gaps)*.99)],
                send_ms=send_time*1000,wait_ms=wait_time*1000,
                frame_ms=(time.perf_counter()-began)*1000,queue_ms=(time.monotonic()-submitted-(time.perf_counter()-began))*1000))
