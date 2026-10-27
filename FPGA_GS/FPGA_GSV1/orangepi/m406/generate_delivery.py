from pathlib import Path
import json,hashlib,html
H=Path(__file__).resolve().parent;E=H/'evidence';ROOT=H.parent
inventory=json.loads((E/'remote_inventory.json').read_text(encoding='utf8'))
rows=json.loads((E/'playback/dev.json').read_text(encoding='utf8'))
checks=[]
for name,info in inventory['files'].items():
 p=ROOT/name
 if p.exists():checks.append(dict(path=name,equal=hashlib.sha256(p.read_bytes()).hexdigest()==info['sha256']))
assert all(c['equal'] for c in checks),checks
manifest=dict(release='M4-06-r1',acceptance='RUNNABLE_LIMITED_BASELINE_NOT_RELIABILITY_PASS',remote=inventory['root']+'/m406',source_checks=checks,runtime=inventory.get('runtime'),files=inventory['files'],media=inventory['media'],service=inventory['service'],ports=inventory['ports_8080_or_50000'],backup=inventory['backup'])
(H/'deployment_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
model=dict(selected=dict(name='Ultralytics YOLOv8s COCO',source='https://github.com/ultralytics/assets/releases/download/v8.3.0/yolov8s.pt',license='AGPL-3.0',role='80类COCO模型，仅使用class_id=9 traffic light作为灯体候选；不是灯色/箭头模型',deployment='yolov8s640_fp16.rknn',backend='RKNN/NPU，申请CORE_2；不宣称核利用率',input='640x640 RGB NHWC uint8，letterbox114；模型内 /255；输出[1,84,8400]解码框/类别分数',schedule='上方12%～66%的左右55%宽图像区域交替；总目标4Hz，每侧约2Hz；每盏实际更新率单列',thresholds=dict(body_candidate=.25,color_gate_body_confidence=.45,nms=.45)),color=dict(backend='CPU/OpenCV',method='原图灯区RGB/HSV发光证据；成对横排暗壳几何与标准三灯位复查；密集纹理否决；两次当前图像确认',limitation='几何支路是受限后处理，非训练模型输出；三灯位是结构假设，非人工ROI或场景答案',tracking='自动灯壳原图匹配≤1.2s，600ms观测失效；跟踪时重新读当前RGB，不沿用旧灯色',shape='圆灯轮廓候选代码存在但尚未真实验收；箭头未支持；OFF不能由漏检推断',control_relation='全部UNKNOWN，未使用旧人工灯区/方向标定，不自动放行'),rejected=[dict(name='已有YOLOv8n COCO',reason='原图抽检漏横排灯，误检路侧装饰物；仅开放类别不足以完成识别'),dict(name='TLoNY tlony-yolov8n.zip（权重实际YOLO11n）',source='https://huggingface.co/mehmetkeremturkcan/traffic-lights-of-new-york/tree/3beca3baaae790cb45916970501af541ae91cb1d',license='AGPL-3.0',classes=['red','green','yellow','redyellow','unknown','pedred','pedgreen','pedunknown'],reason='原图、通用裁剪及放大灯体未有有效检出；Torch/ONNX/RKNN对照，640/1280同样极低分；原训练配置3840。未作生产感知使用'),dict(name='Aleton/trafficlight',license='MIT（发布者声明）',source='https://huggingface.co/Aleton/trafficlight',reason='模型卡明确行人红/绿信号，不能用于机动车灯组；未下载/转换')],conversion='已有.venv405build；Ultralytics8.3.40仅解压至m406/build_vendor，关闭导出时不使用的绘图/云入口，前向层不变。FP16无量化；未新增系统依赖。',parity='evidence/backend_parity.json 六幅真实输入，分数最大差0.0062，候选坐标均差<0.15模型像素；临阈值候选数可有差异，非准确率。')
(H/'model_manifest.json').write_text(json.dumps(model,ensure_ascii=False,indent=2),encoding='utf8')
def table(headers,values):return '| '+' | '.join(headers)+' |\n|'+'|'.join(['---']*len(headers))+'|\n'+'\n'.join('| '+' | '.join(map(str,r))+' |'for r in values)
perf=table(['录像/起点','处理fps','浏览器新帧fps','人车Hz','道路/语义Hz','灯观测Hz'],[[r['video']+' / '+str(r['seek'])+'s',*[f'{r[k]:.2f}'for k in ['processingFps','previewNewFps','detectionFps','roadFps','trafficFps']]]for r in rows])
coverage=[]
for r in rows:
 samples=r['samples'];lights=[b for s in samples for b in s['perception']['traffic'].get('lights',[])];unknown=sum(b['color']=='UNKNOWN'for b in lights);known_times=sum(any(b['color']!='UNKNOWN'for b in s['perception']['traffic'].get('lights',[]))for s in samples);empty=sum(not s['perception']['traffic'].get('lights')for s in samples)
 coverage.append([r['video']+' / '+str(r['seek'])+'s',f'{known_times}/{len(samples)}',f'{empty}/{len(samples)}',f'{unknown}/{len(lights)}'+(f' ({unknown/len(lights):.1%})'if lights else '（无候选）')])
cov=table(['片段','有确定灯色的采样时刻','空观测时刻','候选UNKNOWN比例'],coverage)
stages=['decode','det_preprocess','det_inference','det_postprocess','det_tracking','det_display_tracking','road_preprocess','road_model','lane_postprocess','lane_semantics','traffic_preprocess','traffic_geometry_color','traffic_inference','traffic_postprocess','overlay','jpeg','timeline_lag_ms']
timing=table(['阶段（毫秒）','四片观察范围'],[[k,f'{min(r["stage"].get(k,0)for r in rows):.1f}～{max(r["stage"].get(k,0)for r in rows):.1f}']for k in stages])
age_rows=[]
for r in rows:
 samples=r['samples']; vals=[]
 for section,key in [('detection','inference_age_ms'),('road','age_ms'),('traffic','age_ms')]:
  a=[s.get('perception',{}).get(section,{}).get(key) for s in samples];a=[v for v in a if isinstance(v,(int,float))];vals.append(f'{sum(a)/len(a):.0f}/{max(a):.0f}' if a else '无观测')
 age_rows.append([r['video']+' / '+str(r['seek'])+'s',*vals,r['trafficSkipped'],r['sourceSkipped']])
ages=table(['片段','人车年龄均值/最大ms','道路年龄均值/最大ms','灯观测年龄均值/最大ms','灯采样跳过','播放跳过源帧'],age_rows)
docs=f'''# M4-06-r1：可运行的受限交通灯基线

已实际部署并保留运行。真实夜间横排灯已有红/绿原图、叠加、结构化记录和浏览器连续短片；**本轮可靠性验收未通过，不能作为通用交通灯或本车通行判断使用。** 日间远灯覆盖不足，转灯期间漏检，圆灯/箭头、机动车/行人灯区分和控制归属尚未可靠实现。

## 一键使用

1. 双击 `{ROOT/'oneclick/启动智驾录像演示.cmd'}`。集中配置仍为192.168.0.4，复用现有SSH身份校验与转发；当前密钥可登录，不保存密码。若SSH需要认证，在终端输入；本轮无需sudo。
2. 浏览器自动打开 http://127.0.0.1:18080/ 。点击“夜间红灯”，或“夜间绿灯”，等约1～3秒观察真实灯框、独立编号、右上灯区放大、灯色、源帧/年龄/逐灯Hz。“转灯观察”用于暴露漏检，不能当作连续转灯已通过。
3. 可选四个原视频、播放/暂停、拖动、循环。人车/道路/车道/交通灯开关仅控制画面；不暗中降低感知频率。点击“查看当前原图”对照；“保存原图及叠加”保存在远端m406/evidence/runtime。
4. 灯色已识别也仍显示“控制关系未知，不自动放行”。此时“强制行驶”不会伪造闯红灯告警。道路变道保留r2原规则，不由本轮灯色新增刹车。
5. 停止：双击 `{ROOT/'oneclick/停止智驾录像演示.cmd'}`。关闭启动窗口后远端继续运行；停止入口核对PID/启动身份后正常退出，只清理由该入口记录的SSH转发。
6. 回退：双击 `{ROOT/'oneclick/回退M4-05-r2车道结构.cmd'}`，会安全停新版并启动r2。切回新版双击“切回M4-06-r1交通灯.cmd”。r2目录、旧人车/道路权重、四原视频未覆盖，已实际试切r2→m406及重复启动复用同一PID。

集中配置：`{ROOT/'oneclick/config.json'}`。远端独立目录：`{inventory['root']}/m406`。运行环境：既有 `.venv404/bin/python`，详见deployment_manifest.json。正常服务仅监听127.0.0.1:8080，不启动LIVE、不绑定50000，不需要改变FPGA供电；未改网络、内核或开机自启。

## 实际实现和限制

- 新增YOLOv8s COCO class9灯体候选，RKNN/NPU FP16，640输入；新增CPU灯色、自动成对胶囊灯壳、局部密集纹理否决和短时原图匹配。模型/几何/跟踪来源分别记录；几何评分不是置信度或准确率。模型卡、SHA、许可证、预处理见model_manifest.json。
- 已有YOLOv8n六类人车及YOLOP道路/r2车道算法保留。去掉m406播放线程中已无用途的旧人工灯区、模板及重复Hough推理；旧代码和r2原文件保留。自动模式不会引用旧场景控制方向。
- 交通灯工作线程只保留一个在处理帧和一个可替换最新槽，目标4Hz；左右半图交替，每侧约一半频率。全图几何支路处理上方66%画面；这是通用搜索范围限制，并非场景标定。每灯有自己的source_frame_id、age_ms、source及update_fps。
- 新/变化灯色需两次图像确认，变化时先UNKNOWN；原图匹配最长1.2秒，灯色仍读当前图像；600ms观测失效并移除，切片/跳转/循环清理。不会根据检测缺失输出OFF。
- 当前**控制关系100%UNKNOWN，自动通行覆盖0**。圆灯/箭头真实区分未通过；黄灯、熄灭灯没有可靠正例，不声称已验证。状态变化提示和规则分支通过定向单元检查，但真实红转绿片段未保持同一灯组ID，不能把它写成实测通过。

## 实时性能

以下为最终密集纹理否决版本、SSH转发上的真实Edge浏览器采集；640宽、JPEG70、15fps播放目标。单请求在途，maxInflight=1；按不同epoch:frame源身份计新帧，非HTTP次数或重复JPEG。每窗6.6～13.3秒，原视频时间轴播放、落后跳帧；不代表四片全程或所有场景15fps。

{perf}

{timing}

{ages}

以上年龄来自状态接口采样；灯观测年龄包括空候选观测，不等于每盏灯均被识别。逐灯年龄、失效和UNKNOWN详见原记录。播放源帧跳过同时包括30/约40fps源到15fps播放目标的正常采样，不能直接解释为性能故障。

异步阶段不能简单相加成端到端耗时。主要新增开销为灯体NPU约100ms/半图和CPU几何/颜色/跟踪约90ms/次；没有降低已有目标频率，人车仍按可用最新帧、道路目标8Hz，但竞争下实际频率如表。先前双裁剪同轮约340ms导致过期，已改交替扫描。本轮不再扩大调优。

图龄从香橙派解码完成算起，不是摄像头端到端延迟。灯证据年龄与画面图龄分别显示，超过600ms不继续画旧灯。采样跳过和pending_replaced分开统计；skipped_source_frames为播放主动跳帧，不是网络丢包。详细时窗与计数见evidence/playback/dev.json。

## 覆盖与失败（不是准确率）

每0.5秒采一次状态，同一目标会重复计数；“确定颜色”仍可能误检，不能当准确率。无候选单独列出，不能把它隐去后宣称高覆盖。

{cov}

开发侧目视参考：SC_YJ 99秒两盏横排红灯、105/107秒两盏绿灯在原图可辨；真实运行正例另见exact_source的精确源帧与JSON。SC_BT 55秒能见远小灯体，但灯色无法可靠目辨，不制造确定真值；BT2高架指示标识不等同本车路口灯；YJ2尾灯、路牌作为负样本。

具体失败：

1. COCO把BT装饰灯杆/红色装饰物及YJ2路牌附近结构当灯体候选；多数颜色保持UNKNOWN，灯体误检尚未消除。
2. YJ真实横排红/绿灯仍有漏检，尤其100～107秒转换附近。不能稳定追踪完整转灯过程，真实变化提示未验收通过。
3. 整理证据时发现楼体LED文字被几何支路误认绿灯，原始失败保留于evidence/failure_before_veto。新增局部纹理否决后，该固定负样本被拒绝，两盏真实绿灯保留；这是后处理样例修正，不是模型精度提升，其他招牌/反光仍有风险。
4. 箭头、行人灯类别、本车/邻口方向归属未解决，所有控制结论未知。黄灯、OFF、中国异形灯组没有充分验证。

开发/观察窗口BT约5～17秒、YJ约80～114秒；另留BT20～26、YJ72～79、YJ2 35～41秒作未参与当轮调参的分段核查，记录在holdout.json。它们来自同批四视频，YJ仍是同一路口；**不宣称独立场景泛化**。110秒段与开发观察重叠，仅作为复查，不作为独立保留集。最终纹理否决还需更多独立场景验证，无IoU/mAP或准确率声明。

## 证据和检查

- `查看交付证据.html`：四片浏览器连续MP4、网页截图、原图/源帧灯框对照、失败样本。MP4由真实浏览器WebM按原时间戳导出，奇数尺寸仅补1像素黑边；帧数一致，不插帧；exports.json保留核对。
- `evidence/exact_source`：按已记录灯结果source_frame_id从原片提取的精确原帧与灯框，未重新推理；与运行截图/evidence/runtime分别存放，原视频未污染。
- `evidence/backend_parity.json`：6幅同输入ONNX CPU与RKNN FP16对照，概率最大差0.0062、候选坐标平均误差<0.15模型像素；小阈值变化会改变候选数。这证明转换一致性，不证明识别正确。
- `evidence/targeted_tests.log`：5个定向检查，含真实LED负样本/两灯正例，以及二次确认、状态变化、600ms/epoch清理、未知控制不能放行、停车优先及独立已确认关系规则。合成感知分支不能冒充真实视觉通过。
- `evidence/accepted/checks.json`：浏览器暂停过期、切视频/循环清理、图层控制、未知强制仍停车；真实红/绿截图。未重跑历史FPGA、UDP或离线全套算法验证。
- 日志：远端`m406/state/demo.console.log`、`m406/evidence/runtime/actions.jsonl`。r2源码备份在本地backup及远端m406/backup，SHA/源文件比对见deployment_manifest.json。

## 下一步PC训练需求

预训练COCO/TLoNY已暴露明确域差异，继续盲换权重或扩大UNKNOWN不能完成目标。建议在Windows先核对GPU/CUDA并建立独立训练环境，微调YOLOv8n/s的机动车灯体与行人灯类别；对灯区另标红/黄/绿/熄灭/眩光未知，箭头仅对人工可辨样本标注。先收集约300～500张去重候选并人工复核，覆盖横排/竖排、夜间白芯、远小目标和招牌/尾灯负样本。按不同路口/连续场景划分训练、开发和保留测试，不能随机拆相邻帧；四原片保留测试用途，不直接当已标注训练集。此轮没有训练，没有在板端安装训练依赖。

## 可复制指挥摘要

M4-06-r1独立部署于{inventory['root']}/m406，一键启动已切新版并保留r2回退；未启动LIVE/UDP/FPGA。YOLOv8s RKNN/NPU灯体候选+CPU灯壳/灯色/短跟踪已有真实夜间红绿画面，四片浏览器新帧约14.3～15fps，交通灯观测约3.6～3.8Hz、道路约6.6～7.7Hz。5项定向检查及网页清理/隔离通过。当前远灯、转灯连续ID、箭头/行人灯和控制归属未通过，控制全UNKNOWN不放行；该版本是可见受限基线，不是完整识别验收通过。建议下一阶段PC定向微调，失败原图与来源已保留。
'''
(H/'交付说明.md').write_text(docs,encoding='utf8')
summary=dict(performance=[{k:v for k,v in r.items()if k!='samples'}for r in rows],coverage=coverage,acceptance=manifest['acceptance'])
(E/'performance_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf8')
page=['<!doctype html><meta charset="utf-8"><title>M4-06-r1交付证据</title><style>body{background:#111b26;color:#e9f2ff;font:17px sans-serif;max-width:1300px;margin:auto;padding:24px}a{color:#91d9ff}img,video{max-width:100%;border:1px solid #40566a}section{margin:28px 0}.pair{display:grid;grid-template-columns:1fr 1fr;gap:14px}h1{font-size:27px}</style><h1>M4-06-r1 · 受限交通灯基线</h1><p>已部署并有真实红/绿灯证据，可靠性验收未通过。远灯、转灯连续ID、箭头/行人灯及控制归属未完成。控制全部未知、不自动放行。</p><p><a href="交付说明.md">完整交付说明</a> · <a href="model_manifest.json">模型/许可证</a> · <a href="evidence/performance_summary.json">性能与UNKNOWN覆盖</a></p>']
for color,label in [('RED','红灯'),('GREEN','绿灯')]:
 page.append(f'<section><h2>真实{label}：精确源帧原图与记录结果</h2><div class="pair"><img src="evidence/exact_source/{color}_raw.jpg"><img src="evidence/exact_source/{color}_traffic.jpg"></div><p><a href="evidence/exact_source/{color}.json">同帧结构化结果</a></p><details><summary>网页截图（灯区放大、来源与年龄）</summary><img src="evidence/accepted/{color}_page.png"></details></section>')
for name,label in [('SC_YJ_100','夜间转灯观察：存在漏检，不宣称连续转灯通过'),('SC_BT_7','日间路口：远灯和装饰物难例'),('SC_BT2_9','黄昏高架：不把标识当作本车通行灯'),('SC_YJ2_42','蓝调道路：尾灯/路牌负样本')]:
 snap=json.loads((E/'playback'/f'{name}_snapshot.json').read_text(encoding='utf8'))['snapshot']
 page.append(f'<section><h2>{label}</h2><video controls preload="metadata" src="evidence/browser_videos/{name}.mp4"></video><details><summary>原图、运行叠加与网页截图</summary><div class="pair"><img src="evidence/runtime/{snap}_raw.jpg"><img src="evidence/runtime/{snap}_overlay.jpg"></div><img src="evidence/playback/{name}_page.png"></details><p><a href="evidence/playback/{name}_snapshot.json">运行快照JSON（各异步结果源帧与年龄分别记录）</a></p></section>')
page.append('<section><h2>真实失败保留</h2><p>下图包含楼体LED被误判绿灯的原记录。已增加局部纹理否决，并有真实正/负样本回归；不能推断所有招牌误检已解决。</p><img src="evidence/failure_before_veto/GREEN_traffic.jpg"><p><a href="evidence/failure_before_veto/GREEN.json">失败原始JSON</a></p><img src="evidence/proposals/reference_crops.jpg"><p>依次：装饰物、远灯、路牌负样本、真实绿灯。裁剪仅用于审查，不进入算法。</p></section>')
(H/'查看交付证据.html').write_text('\n'.join(page),encoding='utf8');print('Report generated. Hashes matched:',len(checks))
