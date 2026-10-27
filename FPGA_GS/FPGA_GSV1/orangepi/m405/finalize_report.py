from pathlib import Path
import json,hashlib
base=Path('m405');read=lambda p:json.loads(Path(p).read_text(encoding='utf-8-sig'))
# Run only after final four-window browser check finishes.
full=read(base/'evidence/playback_summary.json');short=read(base/'evidence/delivery/performance.json');assert len(short)==4
rows=[dict(video=r['video'],window_seconds=round(r['seconds'],3),process_fps=round(r['processingFps'],3),preview_new_fps=round(r['previewNewFps'],3),road_fps=round(r['roadUpdateFps'],3),detection_fps=round(r['detectionFps'],3),max_inflight=r['maxInflight'],max_road_age_ms=max(x['roadAge'] or 0 for x in r['samples']),last_stage_mean_ms=r['samples'][-1]['stage']) for r in short]
report=read(base/'evidence/acceptance.json');report.update(final_targeted_playback=rows,road_target_fps=8,controls=read(base/'evidence/delivery/controls.json'),render_optimization='stable Chinese cached; changing numeric age/fps drawn directly, actual values preserved',validation_scope='four complete original videos before final scheduling/render fixes; final code: four recorded real-time ~9s windows, pause/layers/loop checks; same geometry 17 direct audits and 12 consecutive video/seek switches')
(base/'evidence/acceptance.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
p=base/'交付说明.md';s=p.read_text(encoding='utf-8-sig').split('## 最终实测')[0];s+='## 最终实测（SSH浏览器，640宽）\n\n|录像|整段处理 / 新帧fps（调度优化前）|最终处理 / 新帧fps|最终道路 / 人车模型fps|\n|---|---|---|---|\n'
for f,r in zip(full,rows):s+=f"|{r['video']}|{f['processing_fps']:.2f} / {f['browser_new_frame_fps']:.2f}|{r['process_fps']:.2f} / {r['preview_new_fps']:.2f}|{r['road_fps']:.2f} / {r['detection_fps']:.2f}|\n"
s+='\n整段按原时间轴播放约59、32、177、77秒并检查循环；最终设置又完成四段约9秒实拍浏览器短片。原NPU满速道路更新约11fps仍拖累预览，最终道路目标8Hz，页面同时显示实际更新和年龄；人车与预览继续以15fps为目标。变化的年龄/fps改用快速数字绘制，保留真实值。没有用重复图或慢放掩盖。\n\n最终阶段滚动平均（ms；异步并行，不可直接相加）：\n\n|录像|解码|道路预处理 / NPU / 车道后处理|人车NPU / 后处理|叠加 / JPEG|\n|---|---|---|---|---|\n'
for r in rows:
 m=r['last_stage_mean_ms'];s+=f"|{r['video']}|{m['decode']:.1f}|{m['road_preprocess']:.1f} / {m['road_model']:.1f} / {m['lane_postprocess']:.1f}|{m['det_inference']:.1f} / {m['det_postprocess']:.1f}|{m['overlay']:.1f} / {m['jpeg']:.1f}|\n"
s+='\n首轮一次切片卡住的原现场未取得堆栈，不能断言唯一原因。发现旧Perception构造在HTTP重置时修改全局OpenCV线程池的并发隐患，已由legacy_perception继承原方法，仅把全局设置移到启动一次；之后四片直接跳转和12次连续切换通过。暂停道路age状态随主机时间增长，500ms后失效。原算法源码未修改。完整数据acceptance.json；图龄从香橙派源帧解码完成起算，不是摄像头端到端延迟。\n'
p.write_text(s,encoding='utf-8')
m=read(base/'model_manifest.json');m['target_update_fps']=8;(base/'model_manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8')
files={str(p).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in base.glob('*.py') if p.name in ['demo.py','road.py','overlay.py','demo_ops.py','legacy_perception.py']};files['m405/index.html']=hashlib.sha256((base/'index.html').read_bytes()).hexdigest()
for model in ['yolop320.onnx','yolop320_fp16.rknn']:files['m405/'+model]=hashlib.sha256((base/'models'/model).read_bytes()).hexdigest()
(base/'deployment_manifest.json').write_text(json.dumps(dict(release='M4-05-r1',remote_dir='/home/orangepi/fpga_gs_m401_v0_1_2_20261021',files=files),indent=2),encoding='utf-8')
print(json.dumps(rows,ensure_ascii=False,indent=2))
