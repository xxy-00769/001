"""Package actual browser-canvas recordings for portable playback; preserve PTS."""
import json,subprocess
from pathlib import Path
base=Path(__file__).resolve().parent/'evidence';rows=[]
for name in ['SC_BT','SC_BT2','SC_YJ','SC_YJ2']:
 src=base/('SC_YJ2_recheck.webm' if name=='SC_YJ2' else name+'.mp4_640.webm');dst=base/(name+'_actual_preview.mp4')
 subprocess.run(['ffmpeg','-y','-v','error','-i',str(src),'-vf','pad=ceil(iw/2)*2:ceil(ih/2)*2','-vsync','0','-enc_time_base','1/1000','-c:v','libx264','-preset','fast','-crf','22','-pix_fmt','yuv420p','-movflags','+faststart',str(dst)],check=True)
 probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-count_frames','-show_entries','format=duration:stream=codec_name,width,height,nb_read_frames,avg_frame_rate','-of','json',str(dst)]))
 source_probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-count_frames','-show_entries','stream=nb_read_frames','-of','json',str(src)]))
 assert source_probe['streams'][0]['nb_read_frames']==probe['streams'][0]['nb_read_frames'],'export must not duplicate/drop captured frames'
 subprocess.run(['ffmpeg','-v','error','-i',str(dst),'-vsync','0','-f','rawvideo','-'],stdout=subprocess.DEVNULL,check=True)
 rows.append(dict(video=name,source='actual browser canvas capture through SSH',source_file=src.name,source_frame_count=source_probe['streams'][0]['nb_read_frames'],timing='original recording PTS preserved; no fps resampling, captured frame counts equal',probe=probe))
(base/'clip_validation.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2));print('four portable recordings fully decoded')
