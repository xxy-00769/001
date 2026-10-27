"""One main-screen M3 bench: RIGHT TX / FRONT RX / simulated control.
Python 3.9+, standard tkinter and already-installed Pillow. No NIC mutations.
"""
import argparse, collections, dataclasses, json, queue, secrets, socket, struct
import threading, time, multiprocessing
import os, ctypes
from pathlib import Path
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from PIL import Image, ImageDraw, ImageFont, ImageTk
from protocol import *
from video_source import VideoSource, find_ffmpeg
from sender import send_worker

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
    inverse=bytes(0 if v else 255 for v in range(256))
    mask=label.convert('L').tobytes()
    for y in range(label.height):
        expanded=mask[y*label.width:(y+1)*label.width].translate(inverse)
        both=bytearray(label.width*2);both[0::2]=expanded;both[1::2]=expanded
        start=((y+25)*WIDTH+20)*2
        original=int.from_bytes(data[start:start+len(both)],'little')
        data[start:start+len(both)]=(original & int.from_bytes(both,'little')).to_bytes(len(both),'little')
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
        self.source = VideoSource(args.right_fps, getattr(args,'ffmpeg',None))
        if getattr(args,'video',None): self.source.select(args.video, getattr(args,'loop',False))
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
        self.measure_samples=collections.deque();self.telemetry_last=None
        self.board_counts = {}; self.board_last = None; self.board_first = None
        context=multiprocessing.get_context('spawn')
        self.tx_jobs=context.Queue(maxsize=1);self.tx_results=context.Queue(maxsize=8)
        self.tx_stop=context.Event()
        self.tx_worker=context.Process(target=send_worker,args=(self.sock,self.peer,self.session,
            args.right_fps,args.drop_every,self.tx_jobs,self.tx_results,self.tx_stop),daemon=True)
        self.tx_worker.start()
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
                elif msg.kind == TELEMETRY:
                    now=time.monotonic()
                    values=dict(zip(TELEMETRY_FIELDS,TELEMETRY_STRUCT.unpack(msg.payload)))
                    previous=getattr(self,'telemetry_previous',None)
                    if previous and any(((v-previous[k])&0xffffffff)>=0x80000000 for k,v in values.items()):
                        # A PHY/MAC reset can clear only its counters. Retain
                        # event dedup/session state; restart the rate window.
                        self.measure_samples.clear();self.board_first=None;self.board_last=None
                        self.stats['board_counter_resets']+=1
                        self.measure_restart_after=now+getattr(self.args,'warmup',5)
                        self.board_counts.update(window_seconds=0,window_deltas={})
                        for k in ('window_pc_send_fps','window_board_publish_fps','window_display_new_fps','window_front_receive_fps'):
                            self.board_counts.pop(k,None)
                    self.telemetry_previous=values
                    self.board_counts.update({'board_'+k:v for k,v in values.items()})
                    # All four rates use the SAME host-observed stable window.
                    # Board counters are packet-boundary snapshots, not MAC wire timestamps.
                    if now-self.start>=getattr(self.args,'warmup',5) and now>=getattr(self,'measure_restart_after',self.start):
                        sample=dict(values,pc_sent=self.stats['right_frames_sent'],pc_front=self.stats['front_frames'])
                        self.measure_samples.append((now,sample))
                        while len(self.measure_samples)>1 and now-self.measure_samples[1][0]>=60:
                            self.measure_samples.popleft()
                        then,first=self.measure_samples[0];span=now-then
                        if span>0:
                            delta={k:(v-first[k])&0xffffffff for k,v in sample.items()}
                            self.board_counts.update(window_seconds=round(span,3),window_deltas=delta,
                                window_pc_send_fps=delta['pc_sent']/span,window_board_publish_fps=delta['published']/span,
                                window_display_new_fps=delta['displayed_new']/span,window_front_receive_fps=delta['pc_front']/span)
                    self.telemetry_last=now
                elif msg.kind == HEARTBEAT:
                    self.stats['heartbeat'] += 1
                    if msg.flags & 1:
                        now=time.monotonic()
                        if self.board_first is None: self.board_first=(now,msg.frame,msg.offset)
                        if self.board_last:
                            old_time,old_frames=self.board_last
                            self.board_counts['board_publish_fps']=((msg.frame-old_frames)&0xffffffff)/max(.001,now-old_time)
                        self.board_last=(now,msg.frame)
                        self.board_counts.update(board_right_published=msg.frame,
                            board_right_dropped=msg.offset,board_bad_packets=msg.sequence)
                        first_time,first_frames,first_drops=self.board_first
                        span=now-first_time
                        if span>0:
                            self.board_counts.update(board_publish_avg_fps=((msg.frame-first_frames)&0xffffffff)/span,
                                board_drop_delta=(msg.offset-first_drops)&0xffffffff,board_measure_seconds=span)
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
        due=time.monotonic();last_source=None
        while not self.stop.is_set():
            while True:
                try: report=self.tx_results.get_nowait()
                except queue.Empty: break
                self.stats['right_frames_sent']+=int(report['completed'])
                self.stats['tx_packets']+=report['packets']
                self.stats['injected_drops']+=report['dropped']
                self.stats['tx_errors']+=report['errors']
                for key in ('send_ms','wait_ms','frame_ms','queue_ms','gap_min_us','gap_max_us','gap_p99_us'): self.stats['last_'+key]=round(report[key],3)
            if not self.send_video.wait(.1):
                due=time.monotonic()
                continue
            if self.stop.wait(max(0,due-time.monotonic())): break
            prepared=time.perf_counter()
            if self.source.path:
                item=self.source.latest
                if not item or self.source.state in ('eof','error','opening'):
                    self.stop.wait(.02);due=time.monotonic();continue
                generation,index,pixels=item
                if (generation,index)==last_source and self.source.playing.is_set():
                    self.stop.wait(.005);continue
                last_source=(generation,index)
            else: pixels=synthetic(frame)
            self.stats['last_prepare_ms']=round((time.perf_counter()-prepared)*1000,3)
            now=time.monotonic()
            try: self.tx_jobs.put_nowait((frame,int((now-self.start)*1000)&0xffffffff,bytes(pixels),time.monotonic()))
            except queue.Full: self.stats['sender_skipped_frames']+=1
            frame = (frame + 1) & 0xffffffff
            due=max(due+1/self.args.right_fps,time.monotonic())

    def snapshot(self):
        elapsed = max(.001, time.monotonic() - self.start)
        return dict(self.stats, session=self.session,
                    front_fps=self.stats['front_frames'] / elapsed,
                    right_fps=self.stats['right_frames_sent'] / elapsed,
                    requested_right_fps=self.args.right_fps,requested_front_fps=self.args.front_fps,
                    source=self.source.path or 'pattern',source_state=self.source.state,
                    decoded_frames=self.source.frames,decode_read_ms=round(self.source.read_seconds*1000,2),
                    source_error=self.source.error,**self.board_counts,
                    missing_packets=self.assembler.missing,
                    incomplete_frames=self.assembler.dropped,
                    front_duplicates=self.assembler.duplicates,
                    heartbeat_age=round(time.monotonic() - self.last_message, 2) if self.last_message else None)

    def close(self):
        self.stop.set()
        self.source.close();self.tx_stop.set();self.tx_worker.join(timeout=2)
        if self.tx_worker.is_alive(): self.tx_worker.terminate();self.tx_worker.join()
        self.sock.close()
        if self.args.stats:
            Path(self.args.stats).write_text(json.dumps(self.snapshot(), indent=2), encoding='utf-8')

def main():
    global PORT
    ap = argparse.ArgumentParser(description=__doc__)
    config=json.loads((Path(__file__).resolve().parents[2]/'config/m3_endpoints.json').read_text(encoding='utf-8'))
    PORT=int(config['udp_port'])
    ap.add_argument('--bind', default=config['pc_ip'])
    ap.add_argument('--board', default=config['board_ip'])
    ap.add_argument('--right-fps', type=float, default=5)
    ap.add_argument('--front-fps', type=int, choices=[0, 5, 10, 15, 30], default=5)
    ap.add_argument('--drop-every', type=int, default=0)
    ap.add_argument('--auto', choices=['manual', 'unknown', 'allow', 'deny', 'red', 'solid'], default='allow')
    ap.add_argument('--warmup',type=float,default=5,help='seconds excluded before common 60s telemetry window')
    ap.add_argument('--stats', default='m3_stats.json')
    ap.add_argument('--headless', action='store_true')
    ap.add_argument('--seconds', type=float, default=0)
    ap.add_argument('--video', help='Local video decoded by existing FFmpeg')
    ap.add_argument('--ffmpeg', help='Path to existing ffmpeg.exe')
    ap.add_argument('--loop', action='store_true')
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
    sources=ttk.Frame(root);sources.pack(fill='x',before=controls)
    looping=tk.BooleanVar(value=args.loop)
    def choose_file():
        path=filedialog.askopenfilename(title='选择右摄真实视频',filetypes=[('视频','*.mp4 *.mkv *.avi *.mov *.webm'),('所有文件','*.*')])
        if path:
            try: bench.source.select(path,looping.get())
            except Exception as exc: messagebox.showerror('视频源',str(exc))
    ttk.Button(sources,text='选择视频文件',command=choose_file).pack(side='left')
    ttk.Button(sources,text='播放/暂停文件',command=bench.source.toggle).pack(side='left')
    def loop_changed():
        if bench.source.path: bench.source.select(bench.source.path,looping.get())
    ttk.Checkbutton(sources,text='循环（变更后从头播放）',variable=looping,command=loop_changed).pack(side='left')
    ttk.Button(sources,text='切换测试图案',command=lambda:bench.source.select()).pack(side='left')
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
    native=tk.BooleanVar(value=False)
    ttk.Checkbutton(sources,text='前摄原尺寸1280×720',variable=native,
        command=lambda: refresh_image()).pack(side='left')
    def save():
        if bench.latest_image:
            fid, raw = bench.latest_image
            Image.frombytes('RGB', (WIDTH, HEIGHT), raw, 'raw', 'BGR;16').save(f'front_{fid}.png')
    ttk.Button(controls, text='保存前摄PNG', command=save).pack(side='left')
    def refresh_image():
        if bench.latest_image:
            fid,raw=bench.latest_image
            im=Image.frombytes('RGB',(WIDTH,HEIGHT),raw,'raw','BGR;16')
            if not native.get(): im.thumbnail((896,504),Image.Resampling.LANCZOS)
            canvas.image=ImageTk.PhotoImage(im);canvas.configure(image=canvas.image)
            if native.get(): root.geometry('1320x980')
            else: root.geometry('1020x820')
    def refresh():
        nonlocal last_frame
        item = bench.latest_image
        if item and item[0] != last_frame:
            last_frame, raw = item
            refresh_image()
            title.configure(text=f'FRONT_RAW 帧{last_frame}，RGB565原彩色（不含板上滤镜/OSD）')
        snap=bench.snapshot();delta=snap.get('window_deltas',{})
        rate=lambda key: f"{snap[key]:.2f}" if key in snap else '待遥测'
        stats.configure(text=(
            f"请求 {snap['requested_right_fps']:g} fps | 同窗发送 {rate('window_pc_send_fps')} | 板端发布 {rate('window_board_publish_fps')} | 显示新帧 {rate('window_display_new_fps')} | 前摄接收 {rate('window_front_receive_fps')} fps\n"
            f"统计窗 {snap.get('window_seconds',0):.1f}s（预热5s，最长约60s）；发布/显示增量 {delta.get('published','-')}/{delta.get('displayed_new','-')}；隐藏右摄时显示新帧为0属正常\n"
            f"窗内 MAC CRC/溢出 {delta.get('mac_crc','-')}/{delta.get('mac_overrun','-')}；格式/校验/会话/规格拒绝 {delta.get('reject_format','-')}/{delta.get('reject_checksum','-')}/{delta.get('reject_session','-')}/{delta.get('reject_profile','-')}\n"
            f"序号异常/重复 {delta.get('sequence_errors','-')}/{delta.get('duplicate_packets','-')}；申请 {delta.get('begin_requests','-')}，等待 {delta.get('begin_wait_cycles','-')} 个10ns周期；超时/新帧打断 {delta.get('assembly_timeouts','-')}/{delta.get('assembly_aborts','-')}\n"
            f"DDR提交 {delta.get('ddr_beats','-')} 拍；来源 {snap['source_state']}；最近发包间隔最小/P99/最大 {snap.get('last_gap_min_us','-')}/{snap.get('last_gap_p99_us','-')}/{snap.get('last_gap_max_us','-')} us\n"
            f"前摄方向缺包/不完整帧 {snap['missing_packets']}/{snap['incomplete_frames']}；完整统计保存至 {bench.args.stats}"))
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
