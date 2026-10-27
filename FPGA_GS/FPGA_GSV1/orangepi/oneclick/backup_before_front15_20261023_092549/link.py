"""GSV3 adapter. Only LIVE_FRONT may create this transport."""
import collections
import secrets
import socket
import threading
import time
from vendor.protocol import (Message, Assembler, HELLO, WELCOME, HEARTBEAT,
    EVENT, EVENT_ACK, RESULT, RESULT_ACK, FRONT_RAW)
from vision import decide

def newer(a,b):
    return 0 < ((a-b)&0xffffffff) < 0x80000000

class Link:
    def __init__(self, bind, peer, publish, lookup, log, ttl_guard=.1):
        self.session=secrets.randbelow(0xffffffff)+1
        self.peer=peer; self.publish=publish; self.lookup=lookup; self.log=log
        self.sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,4*1024*1024)
        self.sock.bind(bind); self.sock.settimeout(.01)
        self.receive_buffer_bytes=self.sock.getsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF)
        self.assembler=Assembler(self.session)
        self.stats=collections.Counter(); self.stop=threading.Event()
        self.pending=None; self.retry=None; self.latest_event=None
        self.sequence=0; self.last_rx=0.; self.guard=ttl_guard
        self.started=time.monotonic(); self.online=False

    def send(self, msg):
        try: self.sock.sendto(msg.encode(),self.peer)
        except OSError: self.stats['send_errors']+=1

    def receive(self, msg, now):
        if msg.session!=self.session:
            self.stats['wrong_session']+=1; return
        if msg.kind not in (WELCOME,HEARTBEAT,EVENT,RESULT_ACK,FRONT_RAW): return
        self.stats['rx_packets']+=1
        self.last_rx=now
        if msg.kind in (WELCOME,HEARTBEAT):
            self.online=True; self.stats['heartbeat_or_welcome']+=1
        elif msg.kind==FRONT_RAW:
            self.stats['front_fragments']+=1
            raw=self.assembler.feed(msg,now)
            if raw is not None:
                self.stats['complete_frames']+=1
                self.publish(msg.frame,raw,now)
        elif msg.kind==EVENT:
            # ACK before lookup/inference, including duplicates and stale events.
            self.send(Message(EVENT_ACK,self.session,event=msg.event,frame=msg.frame))
            self.stats['event_ack']+=1
            if self.latest_event is not None and not newer(msg.event,self.latest_event):
                self.stats['duplicate_or_old_event']+=1; return
            self.latest_event=msg.event; self.retry=None
            budget=max(0,min(msg.ttl,2000)/1000-self.guard)
            self.pending=(msg,now,now+budget)
            self.stats['events']+=1
            self.log('event',session=self.session,event_id=msg.event,frame_id=msg.frame,
                     action=msg.code,ttl_ms=msg.ttl)
        elif msg.kind==RESULT_ACK:
            if self.retry and (msg.event,msg.sequence)==(self.retry[0].event,self.retry[0].sequence):
                self.stats['result_accepted' if msg.code==1 else 'result_rejected']+=1
                self.log('result_ack',event_id=msg.event,sequence=msg.sequence,accepted=msg.code==1)
                self.retry=None

    def tick(self, now):
        self.assembler.expire(now)
        if self.last_rx and now-self.last_rx>=2 and self.online:
            self.online=False; self.stats['disconnects']+=1
            self.log('link_unknown',explanation='PEER_TIMEOUT')
        if self.pending:
            msg,arrived,deadline=self.pending
            observation=self.lookup(msg.frame,now)
            # A skipped/latest-slot frame may never get inferred; bounded wait.
            due=min(deadline,arrived+.8)
            if observation is not None or now>=due:
                decision=decide(observation,msg.code) if observation is not None and now<deadline else dict(
                    code=0,reason=0,explanation='EXACT_FRAME_MISSING_STALE_OR_EXPIRED')
                self.sequence=(self.sequence+1)&0xffffffff or 1
                result=Message(RESULT,self.session,frame=msg.frame,event=msg.event,
                    sequence=self.sequence,ttl=min(msg.ttl,2000),code=decision['code'],reason=decision['reason'])
                # Original FPGA event deadline remains authoritative; never extend TTL.
                self.send(result); self.stats['results']+=1
                self.log('result',session=self.session,event_id=msg.event,frame_id=msg.frame,
                         sequence=self.sequence,event_wait_ms=round((now-arrived)*1000,2),**decision)
                self.retry=(result,now,deadline) if now<deadline else None
                self.pending=None
        if self.retry:
            msg,sent,deadline=self.retry
            if now>=deadline: self.retry=None; self.stats['result_ack_timeout']+=1
            elif now-sent>=.2:
                self.send(msg); self.retry=(msg,now,deadline); self.stats['result_retries']+=1

    def run(self):
        due=0.
        try:
            while not self.stop.is_set():
                now=time.monotonic()
                if now>=due:
                    self.send(Message(HELLO,self.session,reason=5))
                    self.send(Message(HEARTBEAT,self.session))
                    self.stats['heartbeat_tx']+=1; due=now+.25
                try:
                    data,peer=self.sock.recvfrom(2048)
                    if peer==self.peer: self.receive(Message.decode(data),time.monotonic())
                    else: self.stats['wrong_peer']+=1
                except socket.timeout: pass
                except ValueError: self.stats['bad_packets']+=1
                except OSError:
                    if self.stop.is_set(): break
                    self.stats['receive_errors']+=1
                    self.stop.wait(.01)
                self.tick(time.monotonic())
        finally: self.sock.close()

    def snapshot(self):
        elapsed=max(.001,time.monotonic()-self.started)
        return dict(self.stats,session=self.session,online=self.online,
                    host_elapsed_seconds=round(elapsed,3),
                    front_receive_fps=round(self.stats['complete_frames']/elapsed,3),
                    socket_receive_buffer_bytes=self.receive_buffer_bytes,
                    current_frame_fragments=self.assembler.received,
                    assembly_dropped=self.assembler.dropped,assembly_duplicates=self.assembler.duplicates,
                    hardware_validation='网口2尚未实物联调')
