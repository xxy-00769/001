"""Freeze one successful CAM0-only AE candidate; never program hardware."""
import argparse,hashlib,json,re,shutil
from datetime import datetime
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('build',type=Path);a=p.parse_args()
work=Path(__file__).resolve().parents[1];root=work.parents[1];run=a.build.resolve()
result=json.loads((run/'result.json').read_text(encoding='utf-8-sig'))
assert result['BuildPass'] and result['ExistingConstraintsMet'] and result['InputsUnchanged']
rtr=(run/'report_timing/fpga_gsv1_top.rtr').read_text(errors='replace')
assert 'Design Summary    : All Constraints Met.' in rtr or re.search(r'Design Summary\s*:\s*All Constraints Met\.',rtr)
sections=[]
for s in re.finditer(r'(Setup|Hold|Recovery|Removal|Pulse Width) Summary\((Slow|Fast) Corner\):',rtr):
 body=rtr[s.end():].split('================================',1)[0]
 rows=re.findall(r'(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$',body,re.M)
 assert rows,s.group(0)
 assert all(float(r[0])>=0 and int(r[2])==0 for r in rows),s.group(0)
 sections.append(dict(summary=s.group(0),rows=len(rows),worst_slack_ns=min(float(r[0]) for r in rows),failing_endpoints=sum(int(r[2]) for r in rows)))
assert len(sections)==10
prr=(run/'place_route/fpga_gsv1_top.prr').read_text(errors='replace')
resource=lambda name:float(re.search(r'\| Use of '+name+r'\s+\|\s*([\d.]+)',prr).group(1))
counts=lambda name:sum(int(v) for v in re.findall(r'\|   '+name+r'\s+\|\s*(\d+)',prr))
resources=dict(LUT=counts('LUT'),FF=counts('FF'),DRM=resource('DRM'),PLL=resource('PLL'),CLMA=resource('CLMA'),CLMS=resource('CLMS'))
bit=Path(result['Release']);sha=hashlib.sha256(bit.read_bytes()).hexdigest();assert sha.lower()==result['SHA256'].lower()
base=root/'release/FPGA_GSV1_CAM1_OV3660_3_5_8_ROTATE25_CANDIDATE/source'
for f in (run/'constraints').rglob('*'):
 if f.is_file():assert f.read_bytes()==(base/f.relative_to(run)).read_bytes()
summary=dict(all_existing_constraints_met=True,corner_type_summaries=sections,resources=resources,
 baseline_358=dict(LUT=20774,FF=21372,DRM=93.5,PLL=5),
 readback_R0=dict(LUT=22123,FF=23638,DRM=94.5,PLL=5),constraints_changed=False,board_verified=False,
 limitations=['Existing external PHY PVT/PCB and camera pad electrical model limits inherited; no new electrical signoff.',
 'STA passes existing model; optimized exposure/visual motion require actual readback and same-scene test.',
 'Local DDR/display15fps remains separate from capture30fps and upload request15fps.'])
(work/'reports/final_timing_resources.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
dest=root/'release/FPGA_GSV1_CAM0_OV5640_3_5_9_MOTION_CANDIDATE'
assert not dest.exists(),f'Refuse overwrite {dest}'
dest.mkdir()
for name in ['rtl','vendor','constraints','config']:shutil.copytree(run/name,dest/'source'/name)
shutil.copy2(run/'flow.tcl',dest/'source/flow.tcl')
for name in ['scripts','sim']:shutil.copytree(work/name,dest/'source'/name,ignore=shutil.ignore_patterns('__pycache__'))
shutil.copytree(work/'tools',dest/'tools',ignore=shutil.ignore_patterns('__pycache__','reports'))
shutil.copytree(work/'reports',dest/'reports',ignore=shutil.ignore_patterns('*.vvp','__pycache__','baseline_preview'))
for name in ['result.json','inputs.json','pds_console.log']:shutil.copy2(run/name,dest/'reports'/name)
for name in ['report_timing','place_route']:
 out=dest/'reports'/name;out.mkdir()
 for f in (run/name).iterdir():
  if f.is_file() and f.suffix in ('.rtr','.prr','.prt','.txt','.log'):shutil.copy2(f,out/f.name)
shutil.copy2(root/'reports/M3_05_baseline/OV5640.txt',dest/'reports/OV5640_v2_01.txt')
shutil.copy2(root/'reports/CAM1_358_user_10s_acceptance.json',dest/'reports/CAM1_358_user_10s_acceptance.json')
outbit=dest/bit.name;shutil.copy2(bit,outbit)
artifact=dict(version='3.5.9 CAM0 motion candidate',bitstream=str(outbit),sha256=sha,
 generated_local_time=datetime.fromtimestamp(bit.stat().st_mtime).astimezone().isoformat(),
 generated_utc=result['GeneratedTime'],build=str(run),all_existing_constraints_met=True,
 programmed=False,hardware_verified=False,motion_blur_fixed=False,
 user_closed_task=True,recommended_download_now=False,
 exposure_policy=dict(cap_rows=222,nominal_cap_ms=9.99888,gain_ceiling_x=8,AE=True,AGC=True,mains_Hz=50,night=False),
 baseline_hardware=dict(reference_window_seconds=12,capture_fps=30,ddr_fps=15,display_new_fps=15,exposure_ms=33.14944,gain_x=3.5,geometry_ok=True,bad_delta=0),
 rear_baseline='3.5.8 user10s25/25/25fps only;60s NOT accepted',
 rollback=str(root/'release/FPGA_GSV1_CAM1_OV3660_3_5_8_ROTATE25_CANDIDATE/FPGA_GSV1_CAM1_OV3660_3_5_8_ROTATE25_CANDIDATE_HDMI_1080P60.sbit'))
(dest/'artifact.json').write_text(json.dumps(artifact,ensure_ascii=False,indent=2),encoding='utf-8')
readme=f"""# 3.5.9 CAM0运动清晰度候选（归档，未上板）

用户已反馈当前原曝光画面“感觉挺好的，可以收尾”。本候选仅归档，不要求下载或继续比较；当前板上保留3.5.9-R0只读版，3.5.8仍为可用回退。以下操作仅供将来用户明确要求继续优化时参考。

CAM0实测曝光33.14944ms、实际增益3.5倍；完整采集30fps、DDR发布15fps、可见新帧15fps，12秒坏帧增量0。确认存在长曝光和15fps更新两个独立因素；静态失焦及主观改善尚未确认。

## 本轮实际修改

基于冻结3.5.8，仅CAM0在原OV5640模式表结束后增加AE配置：222行约9.99888ms上限、8倍增益上限、保持自动曝光/增益、关闭夜间延帧、手动50Hz，按实测45.04us行周期修正50/60Hz步长222/185行。先ID5640确认、逐寄存器读改写、保留非目标位并全字节回读；失败不放行CAM0。方向、720p、视野、RGB565、采样沿、PLL、HTS1892/VTS740、ISP不变。

新增/修改：source/rtl/capture/cam0_ae_profile.v、cam0_readback.v、source/rtl/board/fpga_gsv1_top.v、flow.tcl，以及最小读回的UART预留域/被动帧率观察、tools/cam0解码入口。网络功能代码、CAM1配置、约束均未更改，详见reports/source_scope.json。CAM1保持旋转180度/25fps，3.5.8仅10秒验收，未记录60秒通过。

没有修改DDR帧槽或上传请求，采集30与发布/显示15fps差异仍保留；本轮不能承诺动作更新30fps。没有重跑未受影响的算法、滤镜、协议和历史全套测试。

## 交付

唯一曝光优化候选：`{outbit}`

SHA256：`{sha}`

生成：{artifact['generated_local_time']}；UTC：{artifact['generated_utc']}。

回退3.5.8：`{artifact['rollback']}`

未自动下载、未固化Flash。

## 定向验证与构建

生产SCCB配置仿真通过：传感器ID、全部读改写及保留位、首末事务、ACK拒绝、读/写超时、回读不一致、复位重配、失败不假报ready；解码器区分C0O9只读与C0M9曝光配置、过长实际曝光和配置失败。此前只读R0的720行测时/CDC结果沿用；实际R0串口12秒数据见reports/hardware_baseline。详见ae_profile_tests.json及motion_entry_checks.json。

最终完整综合/布局布线/STA通过原约束，10项快慢角setup/hold/recovery/removal/pulse汇总均无失败端点。实际LUT={resources['LUT']}，FF={resources['FF']}，DRM={resources['DRM']}，PLL={resources['PLL']}；详细逐时钟裕量见reports/report_timing/fpga_gsv1_top.rtr，汇总见final_timing_resources.json。继承PHY外部PVT/PCB与摄像头引脚电气模型边界，不把STA当成新的板级电气或画面验收。

早期一次综合被主动停止：审核发现3a0d/e高两位为debug，应掩码3f保留；修正后通过含非零保留位的定向检查，再进行最终构建。不是移相、改驱动或放宽约束。旧只读候选的一次失败时序记录也保留，不作为交付产物。

## 后续有需求时的可选上板操作（本轮不执行）

1. 当前原曝光下记录一次同机位/照明的静止文字、横向移动物体及短暂暗处表现，原图或短片留作对照。不要用FILE_TEST录像或处理后的Web画面替代前摄原图。
2. 手动下载唯一候选；保持接线/机位/照明/香橙派不变，KEY5使前摄可见，KEY6用原图，接COM23。回复“曝光候选已下载”，开发端复用入口直接采12秒；或双击tools/cam0/CHECK_CAM0_MOTION.cmd。
3. 应读到C0M9、ID5640、AEProfileVerified=True、MotionMetricsOK=True、720行、921600像素、坏帧增量0，曝光不超过约10ms、实际增益不超过8倍、夜间关闭，HTS/VTS保持1892/740。采集应仍约30fps；发布/可见新帧预期仍约15fps。读回失败/版本错误会明确提示采样未完成，不假报0曝光。
4. 在同机位和光照下重复一次相同静止文字/横向移动/暗处动作，记录原图或短片。期待移动边缘的曝光拖尾缩短，静态细节/视野不变；动作更新卡顿可能仍在。普通光照和暗处均比较亮度、噪点与拖尾；暗处可变暗、增益噪声可上升，不能以无限曝光或增益换亮度。若曝光未受限、坏帧增长、错行花块或亮度不可接受，回传这一次JSON及观察结果，回退3.5.8。
5. 本轮不要求重测网口、后摄或历史全套；不把HDMI60Hz当作前摄新帧率。

## 取舍与未验收项

33.149ms×3.5倍改为10ms×8倍，线性信号约原69%（约-0.54EV），最终画面取决于AE/ISP与现场光照。50Hz照明通常100Hz光强周期，约10ms可覆盖一周期；亮处更短曝光和PWM/60Hz灯具可能仍有条纹。默认MAINS_50HZ=1可配置，未写其他ISP参数，没有证据认定时域降噪是本轮根因。

优化后的真实曝光/帧率/运动与暗处对比均待用户下载与实测；没有伪造前后图或短片，没有宣称拖影已解决。局部DDR/显示15fps尚未提升；网口2前摄上传15fps保持独立。

回传摘要：3.5.9仅优化CAM0 OV5640自动曝光，原实测33.149ms/3.5倍、30/15/15fps；候选限制约10ms/8倍并修正50Hz防频闪，保留3.5.8后摄旋转25fps及完整功能。定向配置检查和原约束PNR/STA通过，用户认为当前画面可接受，本轮停止安排后续下载/验收；候选仅归档，尚未实测。尚未宣称拖影解决或提升DDR/显示15fps。
"""
(dest/'README.md').write_text(readme,encoding='utf-8')
sums=[hashlib.sha256(f.read_bytes()).hexdigest()+'  '+f.relative_to(dest).as_posix() for f in sorted(dest.rglob('*')) if f.is_file()]
(dest/'SHA256SUMS').write_text('\n'.join(sums)+'\n',encoding='ascii')
print(json.dumps(artifact,ensure_ascii=False,indent=2))
print(json.dumps(summary,indent=2))
