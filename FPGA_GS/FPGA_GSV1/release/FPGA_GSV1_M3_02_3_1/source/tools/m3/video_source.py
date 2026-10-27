"""Bounded FFmpeg decoder. No installer, downloads or private-file discovery."""
import os, shutil, subprocess, threading, time
from pathlib import Path
from protocol import WIDTH, HEIGHT, FRAME_BYTES

def find_ffmpeg(explicit=None):
    candidates = [explicit, shutil.which('ffmpeg'),
        'E:/ruanjianji/FlyingMouse/FlyingMouse Format/resources/ffmpeg/ffmpeg.exe',
        'E:/ruanjianji/jianying/JianyingPro/11.4.0.14410/ffmpeg.exe']
    for p in candidates:
        if p and Path(p).is_file(): return str(Path(p).resolve())
    raise RuntimeError('Video files require an existing FFmpeg executable; use --ffmpeg PATH. Nothing was installed.')

class VideoSource:
    def __init__(self, fps, ffmpeg=None):
        self.fps, self.ffmpeg = fps, ffmpeg
        self.generation = 0; self.latest = None; self.path = None
        self.loop = False; self.state = 'pattern'; self.error = ''
        self.playing = threading.Event(); self.playing.set()
        self.closed = threading.Event(); self.process = None
        self.frames = 0; self.read_seconds = 0.; self.worker = None

    def select(self, path=None, loop=False):
        executable = find_ffmpeg(self.ffmpeg) if path else None
        if path and not Path(path).is_file(): raise ValueError('Video file does not exist: '+str(path))
        self.generation += 1
        previous = self.process; self.process = None
        if previous and previous.poll() is None: previous.terminate()
        if self.worker: self.worker.join(timeout=2)
        self.path = str(path) if path else None; self.loop = loop
        self.latest = None; self.frames = 0; self.read_seconds = 0.; self.error = ''
        self.playing.set(); self.state = 'opening' if path else 'pattern'
        if not path: return
        generation = self.generation
        command = [executable, '-nostdin', '-hide_banner', '-loglevel', 'error',
                   '-threads', '2', '-filter_threads', '1']
        if loop: command += ['-stream_loop', '-1']
        command += ['-i', str(path), '-map', '0:v:0', '-an', '-sn', '-vf',
          f'fps={self.fps},scale={WIDTH}:{HEIGHT}:force_original_aspect_ratio=decrease,'
          f'pad={WIDTH}:{HEIGHT}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1',
          '-pix_fmt', 'rgb565le', '-f', 'rawvideo', 'pipe:1']
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
          creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        self.process = process
        # Drain diagnostic pipe with a bounded tail; it cannot stall decoding.
        def errors():
            for line in process.stderr:
                if generation == self.generation: self.error = (self.error+line.decode(errors='replace'))[-2000:]
        threading.Thread(target=errors, daemon=True).start()
        def decode():
            index=0; due=time.monotonic()
            try:
                while not self.closed.is_set() and generation == self.generation:
                    if not self.playing.is_set():
                        self.state='paused'; self.playing.wait(.05); due=time.monotonic(); continue
                    if self.closed.wait(max(0, due-time.monotonic())): break
                    t=time.perf_counter(); raw=process.stdout.read(FRAME_BYTES)
                    if generation != self.generation: break
                    self.read_seconds += time.perf_counter()-t
                    if len(raw)!=FRAME_BYTES:
                        self.state='error' if process.wait() else 'eof'; break
                    self.frames+=1; self.latest=(generation,index,raw); index+=1; self.state='playing'
                    due += 1/self.fps
                    # Decoder follows the media clock. Sender reads only latest;
                    # late sending skips decoded frames, never queues the video.
            except (OSError, ValueError) as exc:
                if generation==self.generation and not self.closed.is_set(): self.error=str(exc);self.state='error'
            finally:
                if process.poll() is None: process.terminate()
                process.wait(); process.stdout.close(); process.stderr.close()
        self.worker=threading.Thread(target=decode,daemon=True);self.worker.start()

    def toggle(self):
        if self.playing.is_set(): self.playing.clear()
        else: self.playing.set()

    def close(self):
        self.closed.set();self.playing.set()
        if self.process and self.process.poll() is None: self.process.terminate()
        if self.worker: self.worker.join(timeout=2)
