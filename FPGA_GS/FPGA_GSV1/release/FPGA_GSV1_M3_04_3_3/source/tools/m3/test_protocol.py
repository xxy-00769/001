"""Bounded protocol, full-frame oracle and localhost bench smoke tests."""
import dataclasses, socket, struct, time
from types import SimpleNamespace
from protocol import *
from console import Bench, synthetic, pace_until
from PIL import Image

def wait(predicate, timeout=4):
    deadline = time.monotonic() + timeout
    while not predicate():
        assert time.monotonic() < deadline, 'loopback timeout'
        time.sleep(.005)

def main():
    raw = b''.join(struct.pack('<H', (i * 127 + i // 1280) & 65535)
                   for i in range(WIDTH * HEIGHT))
    first = Message(FRONT_RAW, 123, frame=7, count=FRAGMENTS, payload=raw[:PAYLOAD])
    encoded = first.encode()
    assert len(encoded) == 1328 and HEADER.size == 48
    assert encoded[:12] == b'GSV3\x01\x11\x00\x01\x00\x00\x00{'
    assert struct.unpack_from('!HH', encoded, 20) == (1280, 720)
    assert Message.decode(encoded) == first
    for broken in [encoded[:-1], b'BAD!' + encoded[4:], encoded[:7] + b'\x02' + encoded[8:]]:
        try: Message.decode(broken)
        except ValueError: pass
        else: raise AssertionError('malformed packet accepted')
    asm = Assembler(123)
    for i in range(FRAGMENTS - 1, -1, -1):
        msg = dataclasses.replace(first, index=i, offset=i * PAYLOAD,
                                  payload=raw[i * PAYLOAD:(i + 1) * PAYLOAD])
        image = asm.feed(Message.decode(msg.encode()), 1)
        if i == FRAGMENTS - 1: assert asm.feed(msg, 1) is None
    assert image == raw and asm.complete == 1 and asm.duplicates == 1
    assert asm.feed(dataclasses.replace(first, frame=6), 1) is None
    asm.feed(dataclasses.replace(first, frame=8), 2); asm.expire(4.1)
    assert asm.dropped == 1 and asm.missing == 1439
    for i in range(FRAGMENTS):
        image = asm.feed(dataclasses.replace(first, frame=9, index=i, offset=i * PAYLOAD,
                          payload=raw[i * PAYLOAD:(i + 1) * PAYLOAD]), 3)
    assert image == raw and asm.complete == 2
    # Pillow's actual GUI/save decoder must preserve RGB565 primary colors.
    assert list(Image.frombytes('RGB', (3, 1), b'\x00\xf8\xe0\x07\x1f\x00', 'raw', 'BGR;16').getdata()) == [(255,0,0),(0,255,0),(0,0,255)]
    assert len(synthetic(1)) == FRAME_BYTES and synthetic(1) != synthetic(2)
    
    peer = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    peer.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
    peer.bind(('127.0.0.2', PORT)); peer.settimeout(.1)
    bench = Bench(SimpleNamespace(bind='127.0.0.1', board='127.0.0.2', auto='red',
        right_fps=1, front_fps=5, drop_every=0, stats=None))
    try:
        target = ('127.0.0.1', PORT)
        sid = bench.session
        # Exercise real UDP sockets and the shipping receiver/auto-control path.
        for i in range(FRAGMENTS):
            peer.sendto(dataclasses.replace(first, session=sid, frame=44, index=i,
                offset=i * PAYLOAD, payload=raw[i * PAYLOAD:(i+1) * PAYLOAD]).encode(), target)
    
        print('LOOPBACK_DIAG', bench.snapshot(), 'received', bench.assembler.received,
              'elapsed', time.monotonic()-bench.start, flush=True)
        wait(lambda: bench.stats['front_frames'] == 1)
        assert bench.latest_image == (44, raw)
        event = Message(EVENT, sid, frame=44, event=3, code=1)
        peer.sendto(event.encode(), target); peer.sendto(event.encode(), target)
        seen, result = set(), None
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline and (result is None or not {VIDEO_IN, HELLO, EVENT_ACK} <= seen):
            try: data, addr = peer.recvfrom(2048)
            except socket.timeout: continue
            msg = Message.decode(data); seen.add(msg.kind)
            if msg.kind == RESULT:
                result = msg
                peer.sendto(Message(RESULT_ACK, sid, event=msg.event, sequence=msg.sequence, code=1).encode(), target)
        assert result and (result.frame, result.event, result.code, result.reason) == (44, 3, 2, 1)
        assert {VIDEO_IN, HELLO, EVENT_ACK} <= seen
        wait(lambda: bench.stats['result_accepted'] >= 1)
        assert bench.stats['key_events'] == 1 and bench.stats['event_duplicates'] == 1
        peer.sendto(Message(HEARTBEAT,sid,flags=1,frame=10,offset=2).encode(),target)
        wait(lambda: bench.board_first is not None)
        time.sleep(.1)
        peer.sendto(Message(HEARTBEAT,sid,flags=1,frame=13,offset=3).encode(),target)
        wait(lambda: bench.board_counts.get('board_right_published')==13)
        assert bench.board_counts['board_drop_delta']==1 and bench.board_counts['board_publish_avg_fps']>0
        counters=tuple(range(16))
        telemetry=Message(TELEMETRY,sid,payload=TELEMETRY_STRUCT.pack(*counters))
        assert TELEMETRY_STRUCT.unpack(Message.decode(telemetry.encode()).payload)==counters
        try: Message.decode(Message(TELEMETRY,sid,payload=b'bad').encode())
        except ValueError: pass
        else: raise AssertionError('malformed telemetry accepted')
        peer.sendto(telemetry.encode(),target)
        wait(lambda:bench.board_counts.get('board_ddr_beats')==12)
        assert bench.board_counts['board_displayed_new']==14
        peer.sendto(Message(TELEMETRY,sid,payload=TELEMETRY_STRUCT.pack(*[v+100 for v in counters])).encode(),target)
        wait(lambda:bench.board_counts.get('board_ddr_beats')==112)
        peer.sendto(telemetry.encode(),target)
        wait(lambda:bench.stats['board_counter_resets']==1)
        assert bench.board_counts['window_seconds']==0 and event.event in bench.seen_events
        print('M3_HOST_PASS full_frame_bytes=1843200 fragments=1440 malformed_loss_recovery=1 RGB565=1 sockets_bench_control=1')
    finally:
        bench.close(); peer.close()

if __name__ == "__main__": main()

