"""GSV3 v1: shared Windows / Orange Pi transport, no GUI dependency."""
from dataclasses import dataclass
import struct, time

HEADER = struct.Struct('!4sBBBBIIIHHIHHHHIIHBB')
MAGIC, VERSION, PORT = b'GSV3', 1, 50000
WIDTH, HEIGHT, PAYLOAD = 1280, 720, 1280
FRAME_BYTES, FRAGMENTS = WIDTH * HEIGHT * 2, WIDTH * HEIGHT * 2 // PAYLOAD
HELLO, WELCOME, HEARTBEAT, EVENT, EVENT_ACK, RESULT, RESULT_ACK = range(1, 8)
VIDEO_IN, FRONT_RAW = 16, 17
UNKNOWN, ALLOW, DENY = 0, 1, 2

@dataclass(frozen=True)
class Message:
    kind: int
    session: int
    source: int = 0
    frame: int = 0
    timestamp: int = 0
    offset: int = 0
    index: int = 0
    count: int = 0
    event: int = 0
    sequence: int = 0
    ttl: int = 2000
    code: int = 0
    reason: int = 0
    payload: bytes = b''
    flags: int = 0

    def encode(self):
        if len(self.payload) > PAYLOAD:
            raise ValueError('payload exceeds fixed profile')
        return HEADER.pack(MAGIC, VERSION, self.kind, self.source, 1,
                           self.session, self.frame, self.timestamp, WIDTH, HEIGHT,
                           self.offset, len(self.payload), self.index, self.count,
                           self.flags, self.event, self.sequence, self.ttl,
                           self.code, self.reason) + self.payload

    @classmethod
    def decode(cls, data):
        if len(data) < HEADER.size:
            raise ValueError('short header')
        (magic, version, kind, source, fmt, session, frame, timestamp, w, h,
         offset, size, index, count, flags, event, seq, ttl, code, reason) = HEADER.unpack_from(data)
        if magic != MAGIC or version != VERSION or fmt != 1 or (w, h) != (WIDTH, HEIGHT):
            raise ValueError('header/profile')
        if size > PAYLOAD or len(data) != HEADER.size + size:
            raise ValueError('length')
        if kind in (VIDEO_IN, FRONT_RAW):
            if size != PAYLOAD or count != FRAGMENTS or index >= count or offset != index * PAYLOAD:
                raise ValueError('fragment bounds')
            if source != (3 if kind == VIDEO_IN else 0):
                raise ValueError('video source')
        elif size:
            raise ValueError('control payload')
        return cls(kind, session, source, frame, timestamp, offset, index, count,
                   event, seq, ttl, code, reason, data[HEADER.size:], flags)

class Assembler:
    """One bounded front frame; duplicate bitmap, missing-frame timeout."""
    def __init__(self, session):
        self.session = session
        self.frame = None
        self.data = bytearray(FRAME_BYTES)
        self.seen = bytearray(FRAGMENTS)
        self.received = 0
        self.started = 0
        self.complete = self.dropped = self.duplicates = self.missing = 0
        self.finished = False

    def expire(self, now=None):
        now = time.monotonic() if now is None else now
        if self.frame is not None and not self.finished and now - self.started > 2:
            self.dropped += 1
            self.missing += FRAGMENTS - self.received
            self.finished = True

    def feed(self, msg, now=None):
        now = time.monotonic() if now is None else now
        if msg.session != self.session or msg.kind != FRONT_RAW or msg.source != 0:
            raise ValueError('wrong session/source')
        self.expire(now)
        if self.frame != msg.frame:
            if self.frame is not None and ((msg.frame - self.frame) & 0xffffffff) >= 0x80000000:
                return None
            if self.frame is not None and not self.finished:
                self.dropped += 1
                self.missing += FRAGMENTS - self.received
            self.frame, self.started, self.received, self.finished = msg.frame, now, 0, False
            self.seen[:] = bytes(FRAGMENTS)
        if self.seen[msg.index]:
            self.duplicates += 1
            return None
        if self.finished:
            return None
        self.seen[msg.index] = 1
        self.received += 1
        self.data[msg.offset:msg.offset + PAYLOAD] = msg.payload
        if self.received == FRAGMENTS:
            self.complete += 1
            self.finished = True
            return bytes(self.data)
        return None
