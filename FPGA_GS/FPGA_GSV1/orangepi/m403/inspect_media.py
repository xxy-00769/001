"""Read original media metadata and representative decoded frames; no inference labels."""
import cv2, json, hashlib, subprocess, pathlib, time, importlib.util
ROOT=pathlib.Path(__file__).resolve().parents[1]
out=ROOT/'m403/evidence';out.mkdir(exist_ok=True)
manifest=json.loads((ROOT/'m403/media_manifest.json').read_text(encoding='utf-8-sig'))
results=[]
for row in manifest:
    p=ROOT/'media'/row['name']
    assert p.stat().st_size==row['bytes']
    assert hashlib.sha256(p.read_bytes()).hexdigest()==row['sha256']
    probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_streams','-show_format','-of','json',str(p)]))
    cap=cv2.VideoCapture(str(p));fps=cap.get(cv2.CAP_PROP_FPS);n=int(cap.get(cv2.CAP_PROP_FRAME_COUNT));duration=float(probe['format']['duration'])
    samples=[];tiles=[]
    for sec in [duration*x for x in (.01,.12,.25,.4,.55,.7,.85,.96)]:
        cap.set(cv2.CAP_PROP_POS_MSEC,sec*1000);start=time.perf_counter();ok,im=cap.read();ms=(time.perf_counter()-start)*1000
        assert ok,(p,sec)
        pos=cap.get(cv2.CAP_PROP_POS_MSEC)
        fname=row['name'][:-4]+f'_{sec:.2f}.jpg';cv2.imwrite(str(out/fname),im)
        tile=cv2.resize(im,(480,270));cv2.rectangle(tile,(0,0),(480,24),(0,0,0),-1);cv2.putText(tile,f'{row["name"]} {sec:.2f}s',(8,18),0,.52,(255,255,255),1)
        tiles.append(tile);samples.append(dict(request_seconds=sec,opencv_timestamp_ms=pos,decode_ms=ms,file=fname,width=im.shape[1],height=im.shape[0]))
    import numpy as np
    sheet=np.vstack([np.hstack(tiles[i:i+2]) for i in range(0,8,2)]);cv2.imwrite(str(out/(row['name'][:-4]+'_contact.jpg')),sheet)
    cap.release()
    # Inspect actual packet time stamps, not only filename/container fps hints.
    packets=json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','packet=pts_time,dts_time,duration_time','-of','json',str(p)]))['packets']
    pts=sorted(float(x['pts_time']) for x in packets if 'pts_time' in x)
    gaps=[b-a for a,b in zip(pts,pts[1:])]
    item=dict(**row,probe=probe,source_fps=fps,frame_count=n,duration_seconds=duration,pts_count=len(pts),pts_start=pts[0],pts_end=pts[-1],pts_step_min=min(gaps),pts_step_max=max(gaps),samples=samples)
    results.append(item);(out/'media_verified.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
    print(row['name'],fps,n,duration,'PTS step',min(gaps),max(gaps),flush=True)
print('optional', {x:bool(importlib.util.find_spec(x)) for x in ['onnxruntime','rknnlite','PIL']})
