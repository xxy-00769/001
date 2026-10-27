"""One main-screen M3 bench: RIGHT TX / FRONT RX / simulated control.
Python 3.9+, standard tkinter and already-installed Pillow. No NIC mutations.
"""
import argparse, collections, dataclasses, json, queue, secrets, socket, struct
import threading, time
import os, ctypes
from pathlib import Path
import tkinter as tk
from tkinter import ttk
from PIL import Image, ImageDraw, ImageFont, ImageTk
from protocol import *

_timers = threading.local()
if os.name == 'nt':
    _kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    _kernel.CreateWaitableTimerExW.argtypes = [ctypes.c_void_p, ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32]
    _kernel.CreateWaitableTimerExW.restype = ctypes.c_void_p
    _kernel.SetWaitableTimer.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_longlong), ctypes.c_long, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int]
    _kernel.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_uint32]

def pace_until(deadline, stop=None):
    # High resolution per-thread wait: releases the GIL while receiving video.
    # Does not change the machine timer period or catch up with packet bursts.
    delay = deadline - time.monotonic()
    if delay <= 0: return
    if os.name == 'nt':
        if not hasattr(_timers, 'handle'):
            _timers.handle = _kernel.CreateWaitableTimerExW(None, None, 2, 0x1f0003)
        if _timers.handle:
            due = ctypes.c_longlong(-max(1, int(delay * 10000000)))
            if _kernel.SetWaitableTimer(_timers.handle, ctypes.byref(due), 0, None, None, False):
                _kernel.WaitForSingleObject(_timers.handle, 1000)
                return
    if delay > .002:
        if stop is None: time.sleep(delay - .002)
        elif stop.wait(delay - .002): return
    while time.monotonic() < deadline:
        time.sleep(0)

def synthetic(frame):
    # Fast byte fill, RGB565 little endian; different from HDMI desktop.
    row = b''.join(struct.pack('<H', c) * 160 for c in
                   (0x001f, 0x07e0, 0xf800, 0xffe0, 0x07ff, 0xf81f, 0xffff, 0x4208))
    data = bytearray(row * HEIGHT)
    x = (frame * 17) % (WIDTH - 160)
    for y in range(180, 340):
        start = (y * WIDTH + x) * 2
        data[start:start + 320] = b'\xff\xff' * 160
    label = Image.new('1', (300, 24))
    ImageDraw.Draw(label).text((2, 2), f'RIGHT  FRAME {frame:08d}', fill=1)
    label = label.resize((900, 72), Image.Resampling.NEAREST)
    for y in range(label.height):
        for x in range(label.width):
            if label.getpixel((x, y)):
                start = ((y + 25) * WIDTH + x + 20) * 2
                data[start:start + 2] = b'\x00\x00'
    return data

class Bench:
    def __init__(self, args):
        self.args = args
        self.session = secrets.randbelow(0xffffffff) + 1
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 * 1024 * 1024)
        self.sock.bind((args.bind, PORT))
        self.sock.settimeout(.1)
        self.peer = (args.board, PORT)
        self.stop = threading.Event()
        self.send_video = threading.Event()
        self.send_video.set()
        self.stats = collections.Counter()
        self.events = queue.Queue()
        self.assembler = Assembler(self.session)
        self.latest_image = None
        self.last_message = 0
        self.latest_event = None
        self.seen_events = set()
        self.pending_results = {}
        self.result_seq = 0
        self.choice = args.auto
        self.start = time.monotonic()
        for target in (self.receive, self.transmit, self.heartbeat):
            threading.Thread(target=target, daemon=True).start()

    def send(self, msg):
        try:
            self.sock.sendto(msg.encode(), self.peer)
            self.stats['tx_packets'] += 1
        except OSError as exc:
            if not self.stop.is_set():
                self.events.put(f'发送失败: {exc}')

    def heartbeat(self):
        while not self.stop.wait(.25):
            self.send(Message(HELLO, self.session, reason=self.args.front_fps))
            self.send(Message(HEARTBEAT, self.session))
            now = time.monotonic()
            for key, (msg, sent, created) in list(self.pending_results.items()):
                if now - created >= msg.ttl / 1000:
                    self.pending_results.pop(key, None)
                elif now - sent >= .2:
                    self.send(msg)
                    self.pending_results[key] = (msg, now, created)
                    self.stats['result_retries'] += 1

    def receive(self):
        while not self.stop.is_set():
            try:
                data, peer = self.sock.recvfrom(2048)
                if peer != self.peer:
                    continue
                msg = Message.decode(data)
                if msg.session != self.session:
                    self.stats['old_session'] += 1
                    continue
                self.stats['rx_packets'] += 1
                self.last_message = time.monotonic()
                if msg.kind == FRONT_RAW:
                    frame = self.assembler.feed(msg)
                    if frame:
                        self.latest_image = (msg.frame, frame)
                        self.stats['front_frames'] += 1
                elif msg.kind == EVENT:
                    self.send(Message(EVENT_ACK, self.session, event=msg.event, frame=msg.frame))
                    if msg.event not in self.seen_events:
                        self.seen_events.add(msg.event)
                        # Bound dedup state; event ids are monotonic per session.
                        if len(self.seen_events) > 256:
                            self.seen_events = set(sorted(self.seen_events)[-128:])
                        self.latest_event = msg
                        self.events.put(f'KEY{msg.code} 事件={msg.event} 前摄帧={msg.frame}（模拟判定）')
                        self.stats['key_events'] += 1
                        if self.choice != 'manual':
                            self.respond(self.choice)
                    else:
                        self.stats['event_duplicates'] += 1
                elif msg.kind == RESULT_ACK:
                    self.pending_results.pop((msg.event, msg.sequence), None)
                    self.stats['result_accepted' if msg.code == 1 else 'result_rejected'] += 1
                    self.events.put(f'判定ACK 事件={msg.event} 序号={msg.sequence} 接受={msg.code == 1}')
                elif msg.kind == HEARTBEAT:
                    self.stats['heartbeat'] += 1
            except socket.timeout:
                self.assembler.expire()
            except (ValueError, OSError) as exc:
                if not self.stop.is_set():
                    self.stats['bad_packets'] += 1
                    self.events.put(str(exc))

    def respond(self, choice):
        msg = self.latest_event
        if msg is None:
            self.events.put('先按板上KEY1～4；判定只绑定该事件，有效期从FPGA按键时刻计。')
            return
        code, reason = {'unknown': (0, 0), 'allow': (1, 0), 'deny': (2, 0),
                        'red': (2, 1), 'solid': (2, 2)}[choice]
        self.result_seq += 1
        result = Message(RESULT, self.session, frame=msg.frame, event=msg.event,
                         sequence=self.result_seq, ttl=2000, code=code, reason=reason)
        now = time.monotonic()
        self.pending_results[(msg.event, result.sequence)] = (result, now, now)
        self.send(result)

    def transmit(self):
        frame = 0
        while not self.stop.is_set():
            if not self.send_video.wait(.1):
                continue
            pixels = synthetic(frame)
            start = time.monotonic()
            interval = 1 / self.args.right_fps / FRAGMENTS
            next_send = start
            for i in range(FRAGMENTS):
                if self.stop.is_set() or not self.send_video.is_set():
                    break
                due = next_send
                pace_until(due, self.stop)
                if self.args.drop_every and i % self.args.drop_every == self.args.drop_every - 1:
                    self.stats['injected_drops'] += 1
                    continue
                next_send = time.monotonic() + interval
                self.send(Message(VIDEO_IN, self.session, source=3, frame=frame,
                                  timestamp=int((start - self.start) * 1000) & 0xffffffff,
                                  offset=i * PAYLOAD, index=i, count=FRAGMENTS,
                                  payload=pixels[i * PAYLOAD:(i + 1) * PAYLOAD]))
            else:
                self.stats['right_frames_sent'] += 1
            frame = (frame + 1) & 0xffffffff
            delay = start + 1 / self.args.right_fps - time.monotonic()
            if delay > 0:
                self.stop.wait(delay)

    def snapshot(self):
        elapsed = max(.001, time.monotonic() - self.start)
        return dict(self.stats, session=self.session,
                    front_fps=self.stats['front_frames'] / elapsed,
                    right_fps=self.stats['right_frames_sent'] / elapsed,
                    missing_packets=self.assembler.missing,
                    incomplete_frames=self.assembler.dropped,
                    front_duplicates=self.assembler.duplicates,
                    heartbeat_age=round(time.monotonic() - self.last_message, 2) if self.last_message else None)

    def close(self):
        self.stop.set()
        self.sock.close()
        if self.args.stats:
            Path(self.args.stats).write_text(json.dumps(self.snapshot(), indent=2), encoding='utf-8')

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--bind', default='192.168.50.1')
    ap.add_argument('--board', default='192.168.50.2')
    ap.add_argument('--right-fps', type=float, default=5)
    ap.add_argument('--front-fps', type=int, choices=[0, 5, 10, 15, 30], default=5)
    ap.add_argument('--drop-every', type=int, default=0)
    ap.add_argument('--auto', choices=['manual', 'unknown', 'allow', 'deny', 'red', 'solid'], default='allow')
    ap.add_argument('--stats', default='m3_stats.json')
    ap.add_argument('--headless', action='store_true')
    ap.add_argument('--seconds', type=float, default=0)
    args = ap.parse_args()
    if not 0 < args.right_fps <= 30:
        ap.error('right-fps must be in (0,30]')
    bench = Bench(args)
    if args.headless:
        try:
            while not args.seconds or time.monotonic() - bench.start < args.seconds:
                time.sleep(1)
                print(json.dumps(bench.snapshot(), ensure_ascii=False), flush=True)
        except KeyboardInterrupt:
            pass
        finally:
            bench.close()
        return
    root = tk.Tk()
    root.title('FPGA_GSV1 M3 — 前摄原图 / 右摄发送 / 模拟判定（无真实识别）')
    root.geometry('1020x780+20+20')
    controls = ttk.Frame(root); controls.pack(fill='x')
    def toggle():
        if bench.send_video.is_set(): bench.send_video.clear()
        else: bench.send_video.set()
    ttk.Button(controls, text='停止/恢复右摄发送', command=toggle).pack(side='left')
    choice = tk.StringVar(value=args.auto)
    select = ttk.Combobox(controls, textvariable=choice,
                         values=['manual', 'unknown', 'allow', 'deny', 'red', 'solid'], state='readonly')
    select.pack(side='left'); select.bind('<<ComboboxSelected>>', lambda e: setattr(bench, 'choice', choice.get()))
    for label, value in [('允许', 'allow'), ('拒绝', 'deny'), ('未知', 'unknown'), ('红灯模拟告警', 'red'), ('实线模拟告警', 'solid')]:
        ttk.Button(controls, text=label, command=lambda c=value: bench.respond(c)).pack(side='left')
    title = ttk.Label(root, text='前摄原彩色完整帧：等待FPGA上传；工具留主屏，HDMI扩展屏独立播放。'); title.pack()
    canvas = ttk.Label(root); canvas.pack()
    stats = ttk.Label(root, text='', wraplength=1000); stats.pack(fill='x')
    log = tk.Text(root, height=12); log.pack(fill='both', expand=True)
    last_frame = None
    def save():
        if bench.latest_image:
            fid, raw = bench.latest_image
            Image.frombytes('RGB', (WIDTH, HEIGHT), raw, 'raw', 'BGR;16').save(f'front_{fid}.png')
    ttk.Button(controls, text='保存前摄PNG', command=save).pack(side='left')
    def refresh():
        nonlocal last_frame
        item = bench.latest_image
        if item and item[0] != last_frame:
            last_frame, raw = item
            im = Image.frombytes('RGB', (WIDTH, HEIGHT), raw, 'raw', 'BGR;16').resize((896, 504))
            canvas.image = ImageTk.PhotoImage(im); canvas.configure(image=canvas.image)
            title.configure(text=f'FRONT_RAW 帧{last_frame}，RGB565原彩色（不含板上滤镜/OSD）')
        stats.configure(text=json.dumps(bench.snapshot(), ensure_ascii=False))
        while True:
            try: text = bench.events.get_nowait()
            except queue.Empty: break
            log.insert('end', text + '\n'); log.see('end')
        if int(log.index('end-1c').split('.')[0]) > 300: log.delete('1.0', '100.0')
        root.after(100, refresh)
    root.protocol('WM_DELETE_WINDOW', lambda: (bench.close(), root.destroy()))
    refresh(); root.mainloop()

if __name__ == '__main__':
    main()
