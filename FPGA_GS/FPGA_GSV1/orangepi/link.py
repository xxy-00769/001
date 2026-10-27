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
    def __init__(self, bind, peer, publish, lookup, log, ttl_guard=.1, front_fps=15, frame_state=None, reset_live=None):
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
        self.reset_live=reset_live or (lambda *args: None)
        self.epoch=0; self.reconnects=0; self.reconnect_reason=None
        self.quiet_until=0.; self.ever_received=False; self.epoch_started=self.started
        self.session_complete_base=0; self.assembly_drop_base=0; self.assembly_dup_base=0
        self.first_fragment_at=None; self.last_complete_at=None; self.last_video_frame=None
        self.backward_since=None; self.backward_last=None; self.backward_frames=0
        self.feedback=EventFeedback(self.session,self.send,lookup,
            frame_state or (lambda fid,now: dict(received=lookup(fid,now) is not None,
                                               inference_complete=lookup(fid,now) is not None)),
            log,self.stats,ttl_guard)

    def reconnect(self, now, reason):
        # Stop BOTH HELLO and HEARTBEAT for 3s so the FPGA's old 2s session expires.
        # Choose once per confirmed outage, then retain the new session until recovered.
        if now < self.quiet_until or not self.ever_received:
            return
        old=self.session
        session=secrets.randbelow(0xffffffff)+1
        while session==old: session=secrets.randbelow(0xffffffff)+1
        self.session=session; self.epoch+=1; self.reconnects+=1
        self.reconnect_reason=reason; self.quiet_until=now+3
        self.online=False; self.last_rx=0.; self.ever_received=False
        self.assembly_drop_base+=self.assembler.dropped
        self.assembly_dup_base+=self.assembler.duplicates
        self.assembler=Assembler(session)
        self.complete_stamps.clear(); self.telemetry={}
        self.first_fragment_at=self.last_complete_at=self.last_video_frame=None
        self.backward_since=self.backward_last=None; self.backward_frames=0
        self.epoch_started=now;self.session_complete_base=self.stats['complete_frames']
        self.feedback.reset_session(session,now)
        self.reset_live(self.epoch,session,now,reason)
        self.log('session_reconnect',old_session=old,session=session,epoch=self.epoch,
                 reason=reason,quiet_seconds=3,handshake_after_monotonic=self.quiet_until)

    def hello(self, now):
        if now < self.quiet_until: return
        self.send(Message(HELLO,self.session,reason=self.front_fps))
        self.send(Message(HEARTBEAT,self.session))
        self.stats['heartbeat_tx']+=1

    def send(self, msg):
        try: self.sock.sendto(msg.encode(),self.peer); return True
        except OSError: self.stats['send_errors']+=1; return False

    def receive(self, msg, now):
        if now < self.quiet_until:
            self.stats['reconnect_quarantine_packets']+=1; return
        if msg.session!=self.session:
            self.stats['wrong_session']+=1; return
        if msg.kind not in (WELCOME,HEARTBEAT,EVENT,RESULT_ACK,FRONT_RAW,TELEMETRY): return
        self.stats['rx_packets']+=1
        self.last_rx=now
        self.ever_received=True
        if msg.kind in (WELCOME,HEARTBEAT):
            self.online=True; self.stats['heartbeat_or_welcome']+=1
        elif msg.kind==TELEMETRY:
            self.telemetry=dict(zip(TELEMETRY_FIELDS,TELEMETRY_STRUCT.unpack(msg.payload)))
            self.stats['telemetry_packets']+=1
        elif msg.kind==FRONT_RAW:
            self.stats['front_fragments']+=1
            self.last_video_frame=msg.frame
            if self.first_fragment_at is None:self.first_fragment_at=now
            current=self.assembler.frame
            backwards=current is not None and ((msg.frame-current)&0xffffffff)>=0x80000000
            if backwards:
                self.stats['backward_fragments']+=1
                # A single late/duplicate packet cannot reset the session. Require
                # multiple forward-moving older frame starts and 2s without a complete frame.
                if msg.index==0 and (self.backward_last is None or
                        0<((msg.frame-self.backward_last)&0xffffffff)<0x80000000):
                    if self.backward_since is None:self.backward_since=now
                    self.backward_last=msg.frame; self.backward_frames+=1
                last_complete=self.last_complete_at or self.first_fragment_at
                if (self.backward_since is not None and now-self.backward_since>=2 and
                        self.backward_frames>=3 and now-last_complete>=2):
                    self.log('frame_epoch_regression',session=self.session,retained_frame=current,
                             incoming_frame=msg.frame,distinct_older_frames=self.backward_frames)
                    self.reconnect(now,'SUSTAINED_FRAME_REGRESSION');return
            raw=self.assembler.feed(msg,now)
            if raw is not None:
                self.stats['complete_frames']+=1
                self.last_complete_at=now
                self.backward_since=self.backward_last=None;self.backward_frames=0
                self.complete_stamps.append(now)
                self.publish(msg.frame,raw,now)
                self.feedback.frame_received(msg.frame,now,now)
        elif msg.kind==EVENT:
            self.feedback.event(msg,now)
        elif msg.kind==RESULT_ACK:
            self.feedback.ack(msg,now)

    def tick(self, now):
        self.assembler.expire(now)
        if self.ever_received and now-self.last_rx>=2:
            self.online=False; self.stats['disconnects']+=1
            self.log('link_unknown',explanation='PEER_TIMEOUT')
            self.reconnect(now,'PEER_TIMEOUT')
        self.feedback.tick(now)

    def run(self):
        due=0.
        try:
            while not self.stop.is_set():
                now=time.monotonic()
                self.tick(now)
                if now>=due:
                    self.hello(now); due=now+.25
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
        state=('WAITING_RECONNECT' if now<self.quiet_until else
               'CONNECTING' if not self.ever_received else
               'STREAMING' if self.last_complete_at is not None and now-self.last_complete_at<2 else
               'FRAGMENTS_NO_COMPLETE' if self.first_fragment_at is not None else 'WAITING_FRONT_FRAME')
        return dict(self.stats,session=self.session,online=self.online,
                    connection_state=state,session_epoch=self.epoch,reconnects=self.reconnects,
                    reconnect_reason=self.reconnect_reason,
                    reconnect_quiet_remaining_ms=round(max(0,self.quiet_until-now)*1000,1),
                    session_started_monotonic=self.epoch_started,
                    last_video_frame_id=self.last_video_frame,assembly_frame_id=self.assembler.frame,
                    last_complete_monotonic=self.last_complete_at,
                    requested_front_fps=self.front_fps,
                    recent_complete_fps=round((len(stamps)-1)/max(.001,now-stamps[0]),3) if len(stamps)>1 else 0,
                    telemetry=dict(self.telemetry),
                    feedback=self.feedback.snapshot(now),
                    host_elapsed_seconds=round(elapsed,3),
                    front_receive_fps=round((self.stats['complete_frames']-self.session_complete_base)/max(.001,now-self.epoch_started),3),
                    socket_receive_buffer_bytes=self.receive_buffer_bytes,
                    current_frame_fragments=self.assembler.received,
                    assembly_dropped=self.assembly_drop_base+self.assembler.dropped,
                    assembly_duplicates=self.assembly_dup_base+self.assembler.duplicates,
                    hardware_validation='网口2已有真实前摄验收；按键及双口条件请见本轮验收报告')
