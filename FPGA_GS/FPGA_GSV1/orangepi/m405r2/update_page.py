from pathlib import Path
p=Path(__file__).parent/'index.html';s=p.read_text(encoding='utf-8').replace('M4-05-r1','M4-05-r2')
s=s.replace("STOP:'停车'","STOP:'停车',REVIEW:'需核实交通'")
s=s.replace('旧灯色/线型规则5Hz；蓝：模型道路；绿：自动本车道；黄：已配对短时沿用；青：未配对候选，绘制样式不表示实虚线。均非安全通行保证。','蓝：YOLOP道路；浅绿：原图复查本车道；黄实线/绿虚线/灰未知。短时沿用≤500ms；缺失标线不补造。实虚标签来自原图与时序，非二值分割直接输出。')
start=s.index('<details id="calibration">');end=s.index('<details id="diagnostics">')
s=s[:start]+'<details><summary>方法、计数与限制</summary><p>YOLOP道路/二值标线由RKNN/NPU运行；CPU在960宽原图上沿模型候选搜索局部窄标线、检查连续性与可见间隔，并进行三次短时确认。人车框区域不作为虚线间隔。相邻车道需独立外侧标线、透视宽度和道路支持。缺少外侧标线表示未知，不能断言不存在。仅显示已确认局部走廊下限，不表示道路总车道数；序号与同向/对向未知。无人工车道ROI。虚线也不等于安全变道。</p></details>'+s[end:]
s=s.replace('<div class="stats" id="road-performance"></div>','<div class="stats" id="lane-structure"></div><div class="stats" id="road-performance"></div>')
anchor="$('road-mask').checked=s.show_road;";assert anchor in s
s=s.replace(anchor,"""let ls=rg.lane_semantics||{},label={SOLID:'实线',DASHED:'虚线',UNKNOWN:'未知',EXISTS:'存在',ABSENT:'不存在'};$('lane-structure').textContent=['left','right'].map(k=>(k==='left'?'左':'右')+'边界 '+(label[ls[k]?.state]||'未知')+' / 相邻车道 '+(label[ls[k]?.adjacent?.state]||'未知')+'：'+(ls[k]?.reason||'等待')).join('；')+'；局部已确认走廊 '+(ls.confirmed_corridors||0)+'（非道路总数），序号/方向未知。';$('road-performance').textContent+=' · 车道语义实际 '+(rd.semantic_update_fps||0).toFixed(2)+' Hz / 年龄 '+(rg.age_ms??'—')+' ms · 人车结果年龄 '+(dt.inference_age_ms??'—')+' ms';"""+anchor)
p.write_text(s,encoding='utf-8')
