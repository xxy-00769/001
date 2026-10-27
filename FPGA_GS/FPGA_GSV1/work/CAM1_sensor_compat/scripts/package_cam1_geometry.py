# -*- coding: utf-8 -*-
"""Freeze the passive G1 observation without overwriting a published package."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import hashlib
import json
import re
import shutil

root = Path(__file__).resolve().parents[1]
project = root.parents[1]
run = sorted((root / 'build').glob('CAM1_OV3660_3_5_6_G1_OBSERVATION_*'))[-1]
dest = project / 'release/FPGA_GSV1_CAM1_OV3660_3_5_6_G1_OBSERVATION'
base = project / 'release/FPGA_GSV1_CAM1_OV3660_3_5_6_CANDIDATE'
result = json.loads((run / 'result.json').read_text(encoding='utf-8-sig'))
assert result['BuildPass'] and result['ExistingConstraintsMet'] and result['InputsUnchanged']
assert not dest.exists(), 'Never overwrite a release'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
changed = []
for item in json.loads((run / 'inputs.json').read_text(encoding='utf-8-sig')):
    file = run / item['RelativePath']
    assert sha(file).upper() == item['SnapshotSHA256']
    assert sha(Path(item['Source'])).upper() == item['SHA256']
    before = base / 'source' / item['RelativePath']
    if not before.exists() or sha(file) != sha(before):
        changed.append(item['RelativePath'].replace('\\', '/'))
assert changed == ['rtl/board/fpga_gsv1_top.v'], changed
assert 'PASS UART geometry' in (root / 'reports/cam_geometry_uart_tb.log').read_text()
assert json.loads((root / 'reports/G1_decoder_fixture.json').read_text())['last']['geometry']['rows'] == 720
timing = (run / 'report_timing/fpga_gsv1_top.rtr').read_text(errors='replace')
assert 'Design Summary : All Constraints Met.' in timing
sections = {}
for m in re.finditer(r'(?m)^(Setup|Hold|Recovery|Removal|Minimum Pulse Width) Summary\((Slow|Fast) Corner\):', timing):
    rows = []
    pending = []
    for line in timing[m.end():].split('====================================================================================================', 1)[0].splitlines():
        r = re.match(r'\s*(.*?)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$', line)
        if r:
            rows.append(dict(clocks=(' '.join(pending)+' '+r[1]).strip(), slack_ns=float(r[2]),
                             failing_endpoints=int(r[4]), endpoints=int(r[5])))
            pending=[]
        elif line.strip() and not any(v in line for v in ['****', '-----', 'Endpoints', 'Clock', 'TNS', 'THS', 'WPWS']):
            pending.append(line.strip())
    assert rows and all(r['slack_ns'] >= 0 and not r['failing_endpoints'] for r in rows)
    sections[f'{m[1]}_{m[2]}'] = rows
prr = (run / 'place_route/fpga_gsv1_top.prr').read_text(errors='replace')
top = next(l for l in prr.splitlines() if re.match(r'\| fpga_gsv1_top\s+\|', l))
cells = [s.strip() for s in top.split('|')][1:]
resources = dict(LUT=int(cells[1]), FF=int(cells[2]), DRM=float(cells[5]), PLL=int(cells[18]))
for name in ['CLMA', 'CLMS']:
    m = re.search(rf'\| Use of {name}\s+\|\s+(\d+)\s+\|\s+(\d+)', prr)
    assert m
    resources[name] = dict(used=int(m[1]), available=int(m[2]))
old = json.loads((base / 'artifact.json').read_text(encoding='utf-8-sig'))
generated = datetime.fromisoformat(re.sub(r'(\.\d{6})\d+',r'\1',result['GeneratedTime']).replace('Z','+00:00'))
bit = dest / Path(result['Release']).name
summary = dict(version='3.5.6-G1', classification='passive_geometry_observation_not_camera_fix',
    bitstream=str(bit), sha256=result['SHA256'].lower(), generated_utc=result['GeneratedTime'],
    generated_Asia_Shanghai=generated.astimezone(timezone(timedelta(hours=8))).isoformat(),
    resources=resources, STA_summaries=sections, declared_constraints_met=True,
    external_sensor_skew_measured=False, external_PHY_PVT_PCB_signed_off=False,
    board_verified=False, programmed_by_agent=False, changed_vs_356=changed,
    sensor_and_capture_equal_356=True, rollback=old['bitstream'], rollback_sha256=old['sha256'],
    previous_board_result='3.5.6: ID 3660 twice, configured true, error 0; 100 bad / 0 good frames in 8 seconds',
    new_function='top only: original four camera UART words reused for existing geometry fields',
    excluded_failed_build='20261023_205957_974: DDR setup -0.200ns, 13 endpoints; not published')
dest.mkdir(parents=True)
for name in ['rtl', 'vendor', 'constraints', 'config']:
    shutil.copytree(run/name, dest/'source'/name)
shutil.copy2(run/'flow.tcl', dest/'source/flow.tcl')
for name in ['scripts', 'sim']:
    shutil.copytree(root/name, dest/'source'/name)
shutil.copytree(root/'reports', dest/'reports', ignore=shutil.ignore_patterns('*.vvp'))
for name in ['result.json', 'inputs.json', 'pds_console.log']:
    shutil.copy2(run/name, dest/'reports'/name)
for name in ['report_timing/fpga_gsv1_top.rtr', 'place_route/fpga_gsv1_top.prr']:
    shutil.copy2(run/name, dest/'reports'/Path(name).name)
failed = root / 'build/CAM1_OV3660_3_5_6_G1_OBSERVATION_20261023_205957_974'
evidence = dest / 'reports/excluded_failed_bus_expansion'
evidence.mkdir()
for name in ['result.json', 'report_timing/fpga_gsv1_top.rtr']:
    shutil.copy2(failed/name, evidence/Path(name).name)
shutil.copy2(result['Release'], bit)
assert sha(bit) == summary['sha256']
(dest/'artifact.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
readme = f'''# 3.5.6-G1：CAM1有效行列观察候选

这是一次被动观察候选，不是摄像头修复完成版。3.5.6已上板失败：ID两次3660、配置及关键寄存器回读通过，8秒内完整几何好帧0、坏帧增加100。当前尚不知道具体错误行列，不能把HREF极性、尺寸或字节转换中的任意一项认定为根因。

## 本次唯一改动

仅在top复用原四个摄像头串口字。W0..11保留，40字总长、115200 8N1、网络模块及原128位串口接口保持不变。只有top的被动状态拼接与3.5.6不同，其余生产输入逐文件哈希相同。传感器配置表、SCCB、CAM1采集、CAM0、HDMI、DDR、滤镜、协议、PHY和所有约束不变。

W12=C1G1（43314731）；W13有效像素总数；W14=配置错误4位/配置标志4位/几何错误8位/行数16位；W15=坏帧低16位/好帧低16位。W16..39保持0。配置标志低至高为identified、ID完成、configured、failed；配置错误0为成功。两次3660识别及详细配置回读实测证据保留在原3.5.6日志，不用新布局冒充ID值。几何错误bit0行长度、bit1行数、bit2 VS期间DE、bit3饱和、bit4超时。正常是配置完成、几何错误0、行数720、像素921600，好帧持续增长。总像素正确但行长错误仍必须拒绝，不绕过保护。

## 实际检查

生产UART原语级串行检查通过：原40字格式、原PHY字段、重排后的配置/几何字段、整行原子保存及末尾保留0。解码器使用已知字段检查通过，并将旧3.5.6未提供的几何字段明确标为“未提供”。实际PNR和双角落STA在原约束下通过，完整结果见artifact.json和原始rtr/prr。传感器板端外部数据偏斜仍未测量；继承的PHY外部模型也不等同于完整PVT/PCB签核。未重复运行摄像头算法、滤镜、网络业务或历史全套测试。

此前384位诊断总线扩展构建205957_974出现未改DDR域setup -0.200ns（13端点），产物被拒绝交付，原始报告保留在工作目录。随后撤回总线扩展，仅保留top原四字重排，不修改DDR逻辑或约束。

资源：{json.dumps(resources, ensure_ascii=False)}。

## 唯一观察位流

{bit}

生成时间（北京时间）：{summary['generated_Asia_Shanghai']}

SHA256：{summary['sha256']}

## 最短操作

仅下载上述G1，COM23保持连接，回复“G1已下载”。不需要换线、改设置、重启香橙派或重复显示/滤镜测试。我会读取8秒现有串口，依据具体像素/行数/错误位进行下一项最小修正。G1没有改变采集行为，预期后摄仍可能显示无有效帧；这不是通过条件。不要把它当作已修复候选。

回退3.5.6：{old['bitstream']}

回退SHA256：{old['sha256']}。原3.5.5 TXDET1发布包也保持原样。没有自动烧录或固化Flash。
'''
(dest/'README.md').write_text(readme, encoding='utf-8')
lines = [f'{sha(p)}  {p.relative_to(dest).as_posix()}' for p in sorted(dest.rglob('*')) if p.is_file()]
(dest/'SHA256SUMS.txt').write_text('\n'.join(lines)+'\n', encoding='utf-8')
print(json.dumps(summary, ensure_ascii=False, indent=2))
