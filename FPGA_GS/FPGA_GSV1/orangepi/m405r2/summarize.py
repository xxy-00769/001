from pathlib import Path
import json,statistics,hashlib
base=Path(__file__).parent
rows=json.loads((base/'evidence/r2_final/playback.json').read_text(encoding='utf-8'));out=[]
for r in rows:
 ages=[];detages=[];lag=[];types={s:{'SOLID':0,'DASHED':0,'UNKNOWN':0,'adjacent_exists':0} for s in ['left','right']}
 for sample in r['samples']:
  rd=((sample.get('perception') or {}).get('road') or {});dt=sample.get('detection')or{}
  if rd.get('age_ms')is not None:ages.append(rd['age_ms'])
  if dt.get('inference_age_ms')is not None:detages.append(dt['inference_age_ms'])
  if sample.get('stage_ms',{}).get('timeline_lag_ms')is not None:lag.append(sample['stage_ms']['timeline_lag_ms'])
  for side in types:
   v=rd.get('lane_semantics',{}).get(side,{})
   types[side][v.get('state','UNKNOWN')]+=1
   types[side]['adjacent_exists']+=int(v.get('adjacent',{}).get('state')=='EXISTS')
 out.append(dict(video=r['video'],seek=r['seek'],seconds=r['seconds'],processing_fps=r['processingFps'],preview_new_fps=r['previewNewFps'],road_and_semantic_fps=r['roadFps'],detection_fps=r['detectionFps'],max_inflight=r['maxInflight'],stage_mean_ms=r['stage'],road_semantic_age_ms=dict(mean=statistics.mean(ages),max=max(ages)) if ages else None,detector_age_ms=dict(mean=statistics.mean(detages),max=max(detages)) if detages else None,timeline_lag_ms=dict(mean=statistics.mean(lag),max=max(lag)) if lag else None,observations=types,note='0.5s status sampling; state counts are observations, not accuracy or per-frame totals. Ages start at model source decode on this host. No end-to-end camera claim.'))
(base/'evidence/performance.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8')
for r in out:print(r['video'],r['seek'],*[round(r[k],2)for k in ['processing_fps','preview_new_fps','road_and_semantic_fps','detection_fps']],r['road_semantic_age_ms'],r['timeline_lag_ms'])
protected=json.loads((base/'evidence/audit_final/index.json').read_text(encoding='utf-8'))
manifest=dict(version='M4-05-r2',remote_dir='/home/orangepi/fpga_gs_m401_v0_1_2_20261021/m405r2',python='../.venv404/bin/python',assets_reused=['../m405/yolop320_fp16.rknn','../m404/yolov8n.rknn','../media/SC_BT.mp4','../media/SC_BT2.mp4','../media/SC_YJ.mp4','../media/SC_YJ2.mp4'],dependency_changes=[],network_changes=[],udp=False,FPGA='powered off, not tested',files={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in base.glob('*') if p.name in ['demo.py','demo_ops.py','road.py','overlay.py','lane_semantics.py','driving.py','legacy_perception.py','index.html']},final_holdout=protected)
(base/'deployment_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
