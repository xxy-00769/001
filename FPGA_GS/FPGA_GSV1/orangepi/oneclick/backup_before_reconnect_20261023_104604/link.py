"""GSV3 adapter. Only LIVE_FRONT may create this transport."""
import collections
import secrets
import socket
import threading
import time
from vendor.protocol import (Message, Assembler, HELLO, WELCOME, HEARTBEAT,
    EVENT, RESULT_ACK, FRONT_RAW, TELEMETRY, TELEMETRY_STRUCT, TELEMETRY_FIELDS)
from feedback import EventFeedback

class Link:
    def __init__(self, bind, peer, publish, lookup, log, ttl_guard=.1, front_fps=15, frame_state=None):
        if not isinstance(front_fps,int) or not 0<=front_fps<=30:
            raise ValueError('front_fps must be an integer in 0..30')
        self.front_fps=front_fps
        self.session=secrets.randbelow(0xffffffff)+1
        self.peer=peer; self.publish=publish; self.lookup=lookup; self.log=log
        self.sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,4*1024*1024)
        self.sock.bind(bind); self.sock.settimeout(.01)
        self.receive_buffer_bytes=self.sock.getsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF)
        self.assembler=Assembler(self.session)
        self.stats=collections.Counter(); self.stop=threading.Event()
        self.last_rx=0.
        self.started=time.monotonic(); self.online=False
        self.complete_stamps=collections.deque(maxlen=512)
        self.telemetry={}
        self.feedback=EventFeedback(self.session,self.send,lookup,
            frame_state or (lambda fid,now: dict(received=lookup(fid,now) is not None,
                                               inference_complete=lookup(fid,now) is not None)),
            log,self.stats,ttl_guard)

    def send(self, msg):
        try: self.sock.sendto(msg.encode(),self.peer); return True
        except OSError: self.stats['send_errors']+=1; return False

    def receive(self, msg, now):
        if msg.session!=self.session:
            self.stats['wrong_session']+=1; return
        if msg.kind not in (WELCOME,HEARTBEAT,EVENT,RESULT_ACK,FRONT_RAW,TELEMETRY): return
        self.stats['rx_packets']+=1
        self.last_rx=now
        if msg.kind in (WELCOME,HEARTBEAT):
            self.online=True; self.stats['heartbeat_or_welcome']+=1
        elif msg.kind==TELEMETRY:
            self.telemetry=dict(zip(TELEMETRY_FIELDS,TELEMETRY_STRUCT.unpack(msg.payload)))
            self.stats['telemetry_packets']+=1
        elif msg.kind==FRONT_RAW:
            self.stats['front_fragments']+=1
            raw=self.assembler.feed(msg,now)
            if raw is not None:
                self.stats['complete_frames']+=1
                self.complete_stamps.append(now)
                self.publish(msg.frame,raw,now)
                self.feedback.frame_received(msg.frame,now,now)
        elif msg.kind==EVENT:
            self.feedback.event(msg,now)
        elif msg.kind==RESULT_ACK:
            self.feedback.ack(msg,now)

    def tick(self, now):
        self.assembler.expire(now)
        if self.last_rx and now-self.last_rx>=2 and self.online:
            self.online=False; self.stats['disconnects']+=1
            self.log('link_unknown',explanation='PEER_TIMEOUT')
        self.feedback.tick(now)

    def run(self):
        due=0.
        try:
            while not self.stop.is_set():
                now=time.monotonic()
                if now>=due:
                    self.send(Message(HELLO,self.session,reason=self.front_fps))
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
        now=time.monotonic();elapsed=max(.001,now-self.started)
        stamps=[t for t in list(self.complete_stamps) if now-t<=5]
        return dict(self.stats,session=self.session,online=self.online,
                    requested_front_fps=self.front_fps,
                    recent_complete_fps=round((len(stamps)-1)/max(.001,now-stamps[0]),3) if len(stamps)>1 else 0,
                    telemetry=dict(self.telemetry),
                    feedback=self.feedback.snapshot(now),
                    host_elapsed_seconds=round(elapsed,3),
                    front_receive_fps=round(self.stats['complete_frames']/elapsed,3),
                    socket_receive_buffer_bytes=self.receive_buffer_bytes,
                    current_frame_fragments=self.assembler.received,
                    assembly_dropped=self.assembler.dropped,assembly_duplicates=self.assembler.duplicates,
                    hardware_validation='网口2已有真实前摄验收；按键及双口条件请见本轮验收报告')
