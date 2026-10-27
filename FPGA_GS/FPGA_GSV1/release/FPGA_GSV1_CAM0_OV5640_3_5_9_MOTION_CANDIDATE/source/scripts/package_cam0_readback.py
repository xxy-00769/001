"""Freeze only a successful readback build. Never program the board."""
import argparse
import hashlib
import json
import shutil
from datetime import datetime
from pathlib import Path

p=argparse.ArgumentParser();p.add_argument('build',type=Path);a=p.parse_args()
work=Path(__file__).resolve().parents[1];root=work.parents[1]
run=a.build.resolve();result=json.loads((run/'result.json').read_text(encoding='utf-8-sig'))
assert result['BuildPass'] and result['ExistingConstraintsMet'] and result['InputsUnchanged']
bit=Path(result['Release']);sha=hashlib.sha256(bit.read_bytes()).hexdigest()
assert sha.lower()==result['SHA256'].lower()
dest=root/'release/FPGA_GSV1_CAM0_OV5640_3_5_9_READBACK'
assert not dest.exists(),f'Refuse overwrite: {dest}'
dest.mkdir()
for name in ['rtl','vendor','constraints','config']:
    shutil.copytree(run/name,dest/'source'/name)
shutil.copy2(run/'flow.tcl',dest/'source/flow.tcl')
for name in ['scripts','sim']:
    shutil.copytree(work/name,dest/'source'/name,ignore=shutil.ignore_patterns('__pycache__'))
shutil.copytree(work/'tools',dest/'tools',ignore=shutil.ignore_patterns('__pycache__','reports'))
shutil.copytree(work/'reports',dest/'reports',ignore=shutil.ignore_patterns('*.vvp','__pycache__','baseline_preview'))
for name in ['result.json','inputs.json','pds_console.log']:
    shutil.copy2(run/name,dest/'reports'/name)
for name in ['report_timing','place_route']:
    out=dest/'reports'/name;out.mkdir()
    for q in (run/name).iterdir():
        if q.is_file() and q.suffix in ('.rtr','.prr','.prt','.txt','.log'):
            shutil.copy2(q,out/q.name)
shutil.copy2(root/'reports/M3_05_baseline/OV5640.txt',dest/'reports/OV5640_v2_01.txt')
shutil.copy2(root/'reports/CAM1_358_user_10s_acceptance.json',dest/'reports/CAM1_358_user_10s_acceptance.json')
outbit=dest/bit.name;shutil.copy2(bit,outbit)
generated=datetime.fromtimestamp(bit.stat().st_mtime).astimezone().isoformat()
artifact=dict(version='3.5.9-R0 CAM0 read-only baseline',stage='readback before motion optimization',
    bitstream=str(outbit),sha256=sha,generated_local_time=generated,
    build=str(run),all_existing_constraints_met=True,programmed=False,hardware_verified=False,
    exposure_optimization_applied=False,motion_blur_fixed=False,
    baseline='3.5.8 rear rotate180/25fps user10s accepted;60s NOT accepted',
    rollback=str(root/'release/FPGA_GSV1_CAM1_OV3660_3_5_8_ROTATE25_CANDIDATE/FPGA_GSV1_CAM1_OV3660_3_5_8_ROTATE25_CANDIDATE_HDMI_1080P60.sbit'))
(dest/'artifact.json').write_text(json.dumps(artifact,ensure_ascii=False,indent=2),encoding='utf-8')
readme=f'''# 3.5.9-R0 CAM0只读基线候选

这不是拖影修复版。3.5.8不支持CAM0读回，必须先读取实际曝光/增益/行周期和三段本地帧率，才能按证据选择约10ms的AE上限。
没有向CAM0增加任何曝光、增益、时钟、ISP写入。CAM1旋转/25fps、帧槽保护、HDMI、滤镜、双网口和控制逻辑保留；图像应与3.5.8相同。

位流：`{outbit}`

SHA256：`{sha}`

生成：{generated}（本机时区+08:00，以实际字段为准）。未自动烧录或固化Flash。

## 最短操作

1. 手动下载以上唯一读回候选，保持原接线、机位、照明、香橙派程序不变。
2. KEY5让前摄可见（前摄单画面或田字格），此12秒内不切换视图。
3. COM23已连可回复“读回候选已下载”，由开发端直接读取一次12秒；或双击`tools/cam0/CHECK_CAM0_BASELINE.cmd`，勿同时打开两个串口工具。
4. 输出必须有C0O9、ID5640、完整曝光毫秒/增益/HTS/VTS、三段fps、720行/921600像素和坏帧增量。采样失败会明确报“采样未完成”，不作0曝光/0帧率结论。
5. 此阶段无需移动物体、换照明或复测网口/滤镜。优化前后同照明/机位的动静/暗处对比在获得读回后一次安排。真实前摄原图/短片对比尚未取得。

回退位流：`{artifact['rollback']}`

## 验证边界

生产SCCB定向仿真、真实720行HREF测时、84MHz频率观察CDC、解码器合成数据和入口语法已检查。详见reports/directed_tests.json。
首次布局出现未修改网口1协议计数路径setup -0.099ns，不交付；精简读回缓存变量写选择为固定字节移位后重新构建，最终真实STA须All Constraints Met才由打包程序放行。
未重跑未受影响的算法、滤镜、摄像头历史全套或网络回环。源差异见reports/source_scope.json。
采用3.5.8原约束，外部PHY PVT/PCB和摄像头输入引脚电气眼图仍属原模型边界，不能把本次STA写成实物质量已验收。
3.5.8后摄仅10秒25/25/25fps、720行、921600像素、坏帧0，未记为60秒通过。

回传摘要：3.5.9-R0只补CAM0只读基线能力，曝光策略未改，拖影优化尚未完成；等待一次COM23实测后确定最小AE配置。
'''
(dest/'README.md').write_text(readme,encoding='utf-8')
sums=[]
for f in sorted(dest.rglob('*')):
    if f.is_file():sums.append(hashlib.sha256(f.read_bytes()).hexdigest()+'  '+f.relative_to(dest).as_posix())
(dest/'SHA256SUMS').write_text('\n'.join(sums)+'\n',encoding='ascii')
print(json.dumps(artifact,ensure_ascii=False,indent=2))
