"""Export exact recorded traffic source frames, no inference rerun or FPS claim."""
import cv2,json,subprocess
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1];out=ROOT/'m406/evidence/exact_source';out.mkdir(exist_ok=True)
font=ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',24);rows=[]
for color in ('RED','GREEN'):
 s=json.loads((ROOT/'m406/evidence/accepted'/f'{color}.json').read_text())['status'];traffic=s['perception']['traffic'];positive=[b for b in traffic['lights']if b['color']==color];frame=positive[0]['source_frame_id'];lights=[b for b in traffic['lights']if b['source_frame_id']==frame]
 cap=cv2.VideoCapture(str(ROOT/'media'/s['video']));assert abs(cap.get(cv2.CAP_PROP_FPS)-30)<.01,'Only CFR source evidence here';cap.set(cv2.CAP_PROP_POS_FRAMES,frame);ok,raw=cap.read();cap.release();assert ok
 cv2.imwrite(str(out/(color+'_raw.jpg')),raw,[cv2.IMWRITE_JPEG_QUALITY,95]);a=Image.fromarray(cv2.cvtColor(raw,cv2.COLOR_BGR2RGB));d=ImageDraw.Draw(a)
 for b in lights:
  co=(255,60,50)if b['color']=='RED'else(60,255,130)if b['color']=='GREEN'else(200,200,200);box=tuple(map(int,b['box']));d.rectangle(box,outline=co,width=4);d.text((box[0],max(0,box[1]-34)),f"#{b['id']} "+{'RED':'红','GREEN':'绿','UNKNOWN':'不可判'}[b['color']],font=font,fill=co)
 d.rectangle((0,0,raw.shape[1],55),fill=(10,20,30));d.text((10,8),f"源帧证据 {s['video']} / frame={frame} · 复用运行记录 · 控制关系未知",font=font,fill=(240,240,240));cv2.imwrite(str(out/(color+'_traffic.jpg')),cv2.cvtColor(__import__('numpy').array(a),cv2.COLOR_RGB2BGR),[cv2.IMWRITE_JPEG_QUALITY,95])
 record=dict(video=s['video'],source_frame_id=frame,lights=lights,note='原录像CFR精确帧索引；识别结果取自已保存真实运行记录。未重新推理，非实时性能测试。');(out/(color+'.json')).write_text(json.dumps(record,ensure_ascii=False,indent=2));rows.append(record)
(out/'index.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2))
exports=[]
def info(p):
 return json.loads(subprocess.check_output(['ffprobe','-v','error','-count_frames','-select_streams','v:0','-show_entries','stream=nb_read_frames,width,height:format=duration','-of','json',str(p)]))
for p in (ROOT/'m406/evidence/browser_videos').glob('*.webm'):
 target=p.with_suffix('.mp4');subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(p),'-vf','pad=ceil(iw/2)*2:ceil(ih/2)*2','-vsync','0','-enc_time_base','1/1000','-c:v','libx264','-preset','veryfast','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',str(target)],check=True)
 before,after=info(p),info(target);assert before['streams'][0]['nb_read_frames']==after['streams'][0]['nb_read_frames']
 exports.append(dict(file=target.name,before=before,after=after,note='仅偶数尺寸补黑边；不插帧、不重采样帧率；实际新帧fps另由浏览器源帧ID统计'))
(ROOT/'m406/evidence/browser_videos/exports.json').write_text(json.dumps(exports,indent=2))
