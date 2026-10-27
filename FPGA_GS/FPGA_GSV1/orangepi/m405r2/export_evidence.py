import json,subprocess
from pathlib import Path
base=Path(__file__).parent/'evidence';rows=[]
for folder in ['r1','r2_final']:
 for src in (base/folder).glob('*.webm'):
  dst=src.with_suffix('.mp4')
  subprocess.run(['ffmpeg','-y','-v','error','-i',str(src),'-vf','pad=ceil(iw/2)*2:ceil(ih/2)*2','-vsync','0','-enc_time_base','1/1000','-c:v','libx264','-threads','2','-preset','fast','-crf','22','-pix_fmt','yuv420p','-movflags','+faststart',str(dst)],check=True)
  def probe(p):return json.loads(subprocess.check_output(['ffprobe','-v','error','-count_frames','-show_entries','format=duration:stream=nb_read_frames,width,height,avg_frame_rate','-of','json',str(p)]))
  a,b=probe(src),probe(dst);assert a['streams'][0]['nb_read_frames']==b['streams'][0]['nb_read_frames']
  rows.append(dict(file=str(dst),source='actual SSH browser canvas; PTS retained, no fps conversion',source_probe=a,output_probe=b))
(base/'clip_validation.json').write_text(json.dumps(rows,indent=2))
