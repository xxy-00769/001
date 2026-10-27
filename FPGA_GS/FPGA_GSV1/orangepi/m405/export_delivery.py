import json,subprocess
from pathlib import Path
base=Path('m405/evidence/delivery');rows=[]
for name in ['SC_BT','SC_BT2','SC_YJ','SC_YJ2']:
 src=base/(name+'.mp4_actual_preview.webm');dst=base/(name+'_actual_preview.mp4')
 subprocess.run(['ffmpeg','-y','-v','error','-i',str(src),'-vf','pad=ceil(iw/2)*2:ceil(ih/2)*2','-vsync','0','-enc_time_base','1/1000','-c:v','libx264','-preset','fast','-crf','22','-pix_fmt','yuv420p','-movflags','+faststart',str(dst)],check=True)
 def probe(p):return json.loads(subprocess.check_output(['ffprobe','-v','error','-count_frames','-show_entries','format=duration:stream=nb_read_frames,width,height,avg_frame_rate','-of','json',str(p)]))
 a=probe(src);b=probe(dst);assert a['streams'][0]['nb_read_frames']==b['streams'][0]['nb_read_frames'];rows.append(dict(video=name,source='actual browser canvas via SSH, original PTS retained, no fps conversion',probe=b))
(base/'clip_validation.json').write_text(json.dumps(rows,indent=2))
