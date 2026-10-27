"""Package only a frozen, timing-clean M3-02 build and scoped PASS evidence."""
from pathlib import Path
import argparse, datetime, hashlib, json, re, shutil

R = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--build', required=True)
p.add_argument('--check', action='append', required=True, help='case=report_directory')
p.add_argument('--unit', required=True)
p.add_argument('--storage', required=True)
p.add_argument('--perf5', required=True)
p.add_argument('--perf15', required=True)
a = p.parse_args()

def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()

def put(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')

B = Path(a.build).resolve()
b = read(B/'result.json')
assert b['Version'] == 'M3-02 3.1' and b['ProcessingEnable']
assert b['BuildPass'] and b['ExistingConstraintsMet'] and b['InputsUnchanged']
for item in read(B/'inputs.json'):
    assert sha(item['Source']) == item['SHA256'].upper(), item['Source']
    assert sha(B/item['RelativePath']) == item['SnapshotSHA256'].upper(), item
assert sha(b['Release']) == b['SHA256'].upper()
timing = (B/'report_timing/fpga_gsv1_top.rtr').read_text(errors='replace')
assert 'Design Summary : All Constraints Met.' in timing

checks = dict(s.split('=', 1) for s in a.check)
assert set(checks) == {'display', 'reader', 'processing', 'osd', 'cdc', 'epoch', 'core', 'host'}
audit = {}
for name, directory in checks.items():
    d = Path(directory).resolve()
    result = read(d/'result.json')
    assert result['Verdict'] == 'PASS' and result['InputsUnchanged'], (name, result)
    for filename, digest in read(d/'inputs.json').items():
        assert sha(filename) == digest.upper(), (name, filename)
    audit[name] = {'Directory': str(d), 'ConsumedInputsUnchanged': True}

# The old unit runner hashed all RTL/tools, although each binary compiled only
# the files below. Validate every actually consumed source and each PASS marker.
# Its old core/host cases are superseded by the exact current checks above.
unit = Path(a.unit).resolve()
assert read(unit/'result.json')['Verdict'] == 'PASS'
unit_manifest = read(unit/'inputs.json')
scoped = {
    'ram_mac': ['rtl/network/m3_byte_ram.v', 'rtl/network/m3_mac.v', 'sim/m3_mac_tb.sv'],
    'owner': ['rtl/frame/m3_front_owner.v', 'sim/m3_owner_tb.sv'],
    'upload': ['rtl/network/m3_upload.v', 'sim/line_ram_model.sv', 'sim/m3_upload_tb.sv'],
    'control': ['rtl/board/m3_keys.v', 'rtl/display/m3_view_select.v',
                'rtl/display/m1_hint_cdc.v', 'rtl/display/m3_osd.v',
                'rtl/display/m3_text.v', 'sim/m3_control_tb.sv'],
    'right_owner': ['rtl/network/m3_right_store.v', 'rtl/display/m2_rd_buf.v',
                    'rtl/reuse/wr_rd_ctrl_top.v', 'rtl/reuse/wr_cmd_trans.v',
                    'rtl/reuse/wr_ctrl.v', 'rtl/reuse/rd_ctrl.v',
                    'sim/line_ram_model.sv', 'sim/m3_right_owner_tb.sv']}
markers = dict(ram_mac='M3_MAC_PASS', owner='M3_OWNER_PASS', upload='M3_UPLOAD_PASS',
               control='M3_CONTROL_PASS', right_owner='M3_RIGHT_OWNER_PASS')
for case, filenames in scoped.items():
    if case in ['upload', 'right_owner']:
        continue
    for filename in filenames:
        f = R/filename
        assert sha(f) == unit_manifest[str(f)].upper(), (case, filename)
    assert markers[case] in (unit/(case+'_run.log')).read_text()
audit['m3_unchanged_units'] = {'Directory': str(unit),
    'ConsumedSources': {k:v for k,v in scoped.items() if k not in ['upload', 'right_owner']},
    'ConsumedInputsUnchanged': True, 'SupersededCases': ['core', 'host', 'upload', 'right_owner']}
storage = Path(a.storage).resolve()
sr = read(storage/'result.json')
assert sr['Verdict'] == 'PASS' and sr['InputsUnchanged']
assert set(sr['SelectedCases']) == {'upload', 'right_owner'}
sm = read(storage/'inputs.json')
for case in ['upload', 'right_owner']:
    for filename in scoped[case]:
        assert sha(R/filename) == sm[str(R/filename)].upper(), (case, filename)
    assert markers[case] in (storage/(case+'_run.log')).read_text()
audit['m3_storage'] = {'Directory': str(storage), 'ConsumedInputsUnchanged': True,
    'ConsumedSources': {k:scoped[k] for k in ['upload', 'right_owner']}}
perf = {name: read(Path(directory)/'result.json') for name, directory in
        [('5', a.perf5), ('15', a.perf15)]}
for v in perf.values():
    assert v['Verdict'] == 'PASS' and v['SoftwareLoopbackOnly'] and not v['BoardMeasured']
    assert v['Seconds'] >= 60 and v['FileLifecyclePass'] and v['OriginalPNGPass']

dmr = (B/'device_map/fpga_gsv1_top.dmr').read_text(errors='replace')
prr = (B/'place_route/fpga_gsv1_top.prr').read_text(errors='replace')
hierarchy = prr.split('Device Utilization Summary Of Each Module:', 1)[1]
module_rows = [line.split('|')[1].strip() for line in hierarchy.splitlines()
               if line.startswith('|') and len(line.split('|')) > 3]
assert module_rows.count('+ m2_reader.hd.reader') == 3, 'All three physical source readers must be HD'
assert module_rows.count('+ hd.reader') == 1, 'Network RIGHT reader must be HD'
assert not any('sd.reader' in row for row in module_rows), 'Legacy SD reader still instantiated'
filter_rows = []
for line in hierarchy.splitlines():
    if line.startswith('|') and line.split('|')[1].strip() in ['+ row1', '+ row2']:
        cells = line.split('|')
        assert float(cells[6]) == 3, 'Each filter row must consume three physical DRM'
        filter_rows.append(cells[1].strip())
assert len(filter_rows) == 2
bindings = dict(Verdict='PASS', SynthesizedHDReaders=4, LegacySDReaders=0,
                FilterDRM=6, Report=str(B/'place_route/fpga_gsv1_top.prr'),
                ReportSHA256=sha(B/'place_route/fpga_gsv1_top.prr'),
                TopSHA256=sha(B/'rtl/board/fpga_gsv1_top.v'))
def resource(text, name):
    return float(re.search(r'\|\s*'+re.escape(name)+r'\s*\|\s*([\d.]+)', text).group(1))
metrics = {name: resource(dmr, name) for name in ['FF', 'LUT', 'DRM', 'APM', 'PLL']}
metrics.update(CLMA=resource(prr, 'Use of CLMA'), CLMS=resource(prr, 'Use of CLMS'))
metrics['CLBPercent'] = 100*(metrics['CLMA']+metrics['CLMS'])/10700
mins = {}
for section in ['Setup Summary(Slow Corner):', 'Hold Summary(Fast Corner):',
                'Recovery Summary(Slow Corner):', 'Removal Summary(Fast Corner):']:
    block = timing.split(section, 1)[1].split('====', 1)[0]
    values = [float(m.group(1)) for m in re.finditer(
        r'^\s*([-+]?\d+\.\d+)\s+[-+]?\d+\.\d+\s+\d+\s+\d+\s*$', block, re.M)]
    # Most rows include clock names; inferred long names wrap to a numeric row.
    values += [float(m.group(1)) for m in re.finditer(
        r'^\s*\S+\s+\S+\s+([-+]?\d+\.\d+)\s+[-+]?\d+\.\d+\s+\d+\s+\d+\s*$', block, re.M)]
    assert values, section
    mins[section] = min(values)
assert min(mins.values()) >= 0, mins
metrics.update(Build=b, MinSlackNs=mins, ExternalIoTimingSignoff=False)
instant = datetime.datetime.fromisoformat(re.sub(r'(\.\d{6})\d+', r'\1', b['GeneratedTime']).replace('Z', '+00:00'))
shanghai = instant.astimezone(datetime.timezone(datetime.timedelta(hours=8)))
D = R/'release/FPGA_GSV1_M3_02_3_1'
assert not D.exists(), 'Preserve existing releases'
bit = D/'FPGA_GSV1_M3_02_3_1_HD_REAL_VIDEO.sbit'

report = f'''# M3-02 3.1 交付报告

## 结果与产物

本版完成代码、针对性验证、综合/布局布线及现有完整约束STA，通过后冻结打包；**尚未烧录/上板验收**。输出标准1920×1080逐行30Hz，原始采集/DDR/网络仍1280×720 RGB565。3.0与2.1发布包保留。

- 位流：`{bit.as_posix()}`
- 版本：M3-02 3.1完整处理版；工程`FPGA_GSV1_M3_02.pds`。
- 位流生成时间：{shanghai.isoformat()}（上海），{instant.isoformat()}（UTC）。
- SHA256：`{b['SHA256']}`
- 冻结构建：`{B.as_posix()}`；源码与构建快照SHA均一致。

## 刚改了什么、有什么用

1. `rtl/display/m31_*`与生产top：标准1080p30时序；单画面1280×720原像素居中，四格各960×540，直接floor(4*n/3)采样720p原帧。扩大坐标和滤波行存储，保留原图/灰度/均值/二值/Y-Cb-Cr三栏、中文/驾驶反馈。来源选择1拍、算法4拍、OSD2拍、最终输出1拍，像素/同步/坐标一致。发布前从综合层级发现并补齐CAM0实例漏传的HD_DISPLAY参数；最终四路均选中HD读者，无旧SD读者。
2. `m31_rd_buf.v`：每行80个256bit返回、640 native word行步进、8192像素环形缓存、三行预取；保留CDC、旧返回排空、真实完成判定及欠载保护。前摄独立上传读者与三帧槽未改成显示借用。
3. `tools/m3/console.py`、`video_source.py`、`sender.py`：真实视频文件选择、播放/暂停/循环/测试图切换；FFmpeg按时间戳解码/等比补边/RGB565LE。仅保留最新解码帧、容量1发送队列，慢时跳帧。前摄原尺寸/适应窗口、原始PNG、模拟判定保留。
4. `m3_net_core.v`：心跳新增板端完整发布/组装丢帧/坏包统计，单次异常不会被尾片重复计数；发送头分级和快照移位，去掉校验和与可变索引长组合路径。视频包长/MTU及原图颜色不变。
5. `config/m3_endpoints.json`集中端点，构建生成硬件常量。网口1本轮共用联调；最终网口1右摄、网口2香橙派前摄/控制，双会话/第二PHY未集成，M4未开始。

## 为什么交付30Hz、约1fps瓶颈证据

148.5MHz首次实际构建未闭合（像素setup −7.995ns，DDR −1.981ns），按任务允许交付74.25MHz/1080p30。OSD分级与网络头分级后，30Hz路由仍定位到panel_y→来源选择→增益→色度路径−0.701ns，增加匹配的选择寄存级后构建通过。未降低保护、放宽约束或新增false path。

旧图案准备34.63ms；1440次逐包等待合计838.99ms是约1fps主要软件瓶颈。改为批量图案生成、复用封包、独立发送进程精确逐包节奏，避免Windows短等待粒度和GIL竞争；发送期间可能占用一个CPU核心，不使用无界突发。

## 实际验证

|检查|结果与边界|
|---|---|
|新1080生产显示全尺寸|单画面+四格共4,147,200输出像素，图像2,995,200；四份完整720p来源/行列独立期望，14,400burst，完整行列/接缝/环回/合法间隙，PASS。四路DDR快照由BFM提供，不冒称物理四路捕获/PHY仿真|
|真实256bit写/32bit读vendor RAM|35,840像素、32行、4次环回，高低半字/1:1与3/4采样/两拍读延迟，PASS|
|真实DRM滤波定点参考|153,600有效样本、1280/1920全宽、五模式、960/540接缝，PASS；两行6个GTP_DRM18K|
|实际综合层级绑定|三个物理来源HD读者+一个网络HD读者，无旧SD读者；滤波每行3 DRM共6，PASS。补上模块级全尺寸仿真未覆盖的顶层参数选择检查|
|真实中文OSD及HDMI AVI|2,592,004样本、21,985字形像素，五视图/五模式/六反馈、两拍对齐、VIC34与AVI校验和，PASS|
|CDC/旧epoch|2ns毛刺不加credit；80拍跨SOF旧返回丢弃、排空后复位，PASS|
|网络核心|实际IPv4校验和、完整1280字节RAW载荷、坏包/缺包恢复、丢帧计数、会话/控制去重与有效期，PASS|
|必要原功能|MAC/FCS/DRM、双读者58项、上传1440片/460800word反压/中止恢复、六键/停车优先35项，PASS。未消费的全目录哈希差异不充作失败，打包逐个核对实际编译文件；旧core/host结果由本版检查替代|
|文件与原图|本地生成MP4夹具；暂停/恢复/循环/EOF/换源；640×480→720p两边160像素补黑；原始PNG1280×720及RGB565原色，PASS。没有使用/下载道路素材|
|主机协议|本版工具精确输入哈希一致、全1,843,200字节前摄、颜色/控制/心跳统计，PASS|

60秒双向并发**软件回环**（前摄/控制/心跳由软件对端模拟，非FPGA实测）：

|右摄请求|右摄完整接收/秒|前摄完整接收/秒|右摄不完整|控制ACK/判定|
|---|---:|---:|---:|---|
|5fps|{perf['5']['ActualRightCompleteFps']:.4f}|{perf['5']['ActualFrontReceiveFps']:.4f}|0|60/60|
|15fps|{perf['15']['ActualRightCompleteFps']:.4f}|{perf['15']['ActualFrontReceiveFps']:.4f}|0|60/60|

5fps接近目标，15fps未达；15请求最近一帧75.58ms（send14.43ms、wait54.87ms），跳过100个旧源帧，前摄仍约5fps。测量窗口结束时在途帧可能造成发送与对端累计差1。解码raw-pipe阻塞读耗时包含源节奏等待，不当作纯解码CPU时间。**板端发布/丢帧/吞吐和720p30均未实测达标**。

## 资源与时序

|指标|3.0|3.1实际|
|---|---:|---:|
|FF|12560|{metrics['FF']:.0f}|
|LUT|14516|{metrics['LUT']:.0f}|
|DRM|60.5|{metrics['DRM']:g}/134|
|CLMA|2676|{metrics['CLMA']:.0f}/6450|
|CLMS|1729|{metrics['CLMS']:.0f}/4250|
|CLB合计|41.17%|{metrics['CLBPercent']:.2f}%|
|APM|6.5|{metrics['APM']:g}/84|
|PLL|4|{metrics['PLL']:g}/5|

现有完整约束`All Constraints Met`；最差setup {mins['Setup Summary(Slow Corner):']:+.3f}ns、hold {mins['Hold Summary(Fast Corner):']:+.3f}ns、recovery {mins['Recovery Summary(Slow Corner):']:+.3f}ns、removal {mins['Removal Summary(Fast Corner):']:+.3f}ns。主时钟：系统50MHz、DDR100MHz/IO400MHz、像素74.25MHz、HDMI-IN74.25MHz、配置10MHz、摄像头参考25MHz、RGMII125MHz；摄像头像素输入按84.0336MHz约束、转换后42.0168MHz。PLL已用满。

DRM增加主要来自四个读RAM不再仅使用低半字：每路实际4→8 DRM（+16），滤波4→6（+2），字形流水推断ROM（+2.5），合计60.5→81。这是恢复全720p像素所需实际映射，非只按滤波增长估计。

外部IO输入/输出延时仍未完整签核，工具存在相关未约束IO告警，不能把内部STA等同PHY/HDMI外部电气签核。未运行实物HDMI/网口/镜头清晰度、烧录、Flash和网口2测试。

## 用户怎么测试、看到什么

完整命令/手动网络设置/逐步正常与失败现象见[上板说明](../docs/M3_02_board_test.md)。CAM0前、CAM1后；电脑HDMI-OUT→板HDMI-IN，扩展屏720p60；板HDMI-OUT→普通1080p显示器；网口1直连1Gbps。手动有线IP192.168.50.1/24，板192.168.50.2，UDP50000，无需网关/DNS。

```powershell
cd E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1
python -X utf8 tools/m3/console.py --bind 192.168.50.1 --board 192.168.50.2 --video "E:/videos/road.mp4" --loop --ffmpeg "E:/ruanjianji/FlyingMouse/FlyingMouse Format/resources/ffmpeg/ffmpeg.exe" --right-fps 5 --front-fps 5 --auto allow --stats m31_stats.json
```

请替换自己的文件路径；Python3.9+/Pillow/tkinter及已有FFmpeg，未安装依赖。不带`--video`用测试图；GUI可选文件/播放暂停/循环/原尺寸前摄。CLI加`--headless --seconds 60 --stats m31_board_60s.json`执行独立60秒板端统计，勿与GUI同时占50000端口。

1. 用户自行加载本版，监视器应识别1920×1080/30Hz。KEY5前→后→左→右→田字格；单画面1:1居中带设计黑边、四格全屏且来源独立。无信号/错块/重复/裁切为失败。
2. 选择道路文件，右摄单画面和右下格持续同一内容，左摄扩展桌面独立。暂停为静帧、恢复继续、循环回头；停发约3秒右摄无信号，恢复完整画面。逐渐落后/残片为失败。
3. KEY6五模式及后摄视角切换后，电脑仍CAM0原彩色；原尺寸开关与保存PNG1280×720无OSD。电脑跟随滤镜/来源/变小为失败。
4. KEY1～4本地LED立即响应并出现模拟判定；长按不连发，KEY4停车优先，旧回包不覆盖新动作。断线约2秒UNKNOWN，重连恢复。其他来源永久卡死/旧告警复活为失败。
5. 回传60秒JSON中请求值、完整TX、`board_publish_avg_fps`及`board_drop_delta`、完整FRONT接收分别统计；先5fps再手动试15fps，不把软件回环当板端实测。

## 遗留与下一步

本版待用户实测显示器30Hz兼容、四路/所有滤镜/真实文件/原图保存和并发性能。未达到15fps及720p30；源图焦距与光照需从保存原图判断。网口2、独立双会话、香橙派真实识别留后续M3分流/M4，本轮未实现。没有自动烧录、固化Flash、修改系统网络或安装软件。

## 回传指挥对话

M3-02 3.1已构建打包（未上板）：1080p30，单720p1:1居中/四格960×540直接采样，滤镜/中文同步适配；真实文件/暂停/循环/前摄原尺寸/集中端点已接入。全尺寸4,147,200像素及RAM/DRM/CDC/旧返回/所有权/控制检查PASS。现有STA通过，setup {mins['Setup Summary(Slow Corner):']:+.3f}ns、hold {mins['Hold Summary(Fast Corner):']:+.3f}ns，FF{metrics['FF']:.0f}/DRM{metrics['DRM']:g}/CLB{metrics['CLBPercent']:.2f}%/PLL5。60秒软件回环请求5/15实得4.88/13.31fps，FRONT约5fps，非板端吞吐；15/30未达。位流{bit.as_posix()}，生成{shanghai.isoformat()}。待上板显示/文件/性能验收；网口2/M4未开始。
'''
put(R/'reports/M3_02_build_metrics.json', metrics)
put(R/'reports/M3_02_bindings.json', bindings)
(R/'reports/M3_02_delivery.md').write_text(report, encoding='utf-8')

D.mkdir()
shutil.copy2(b['Release'], bit)
assert sha(bit) == b['SHA256']
for folder, ext in [('report_timing', '.rtr'), ('device_map', '.dmr'), ('place_route', '.prr')]:
    shutil.copy2(B/folder/('fpga_gsv1_top'+ext), D/(folder+ext))
for file in ['inputs.json', 'result.json']:
    shutil.copy2(B/file, D/('build_'+file))
shutil.copy2(B/'pds_console.log', D/'pds_console.log')
shutil.copy2(B/'place_route/clock_utilization.txt', D/'clock_utilization.txt')
for name, item in audit.items():
    src = Path(item['Directory']); dst = D/'verification'/name; dst.mkdir(parents=True)
    for f in src.iterdir():
        if f.suffix in ['.log', '.json']:
            shutil.copy2(f, dst/f.name)
for label, directory in [('software_duplex_5fps', a.perf5), ('software_duplex_15fps', a.perf15),
                         ('aspect_fixture', R/'reports/M3_02_aspect')]:
    shutil.copytree(directory, D/'verification'/label, ignore=shutil.ignore_patterns('*.vvp', '__pycache__'))
S = D/'source'; S.mkdir()
for folder in ['rtl', 'vendor', 'constraints', 'config']:
    shutil.copytree(B/folder, S/folder)
for folder in ['scripts', 'sim', 'tools/m3']:
    shutil.copytree(R/folder, S/folder, ignore=shutil.ignore_patterns('__pycache__'))
shutil.copy2(B/'flow.tcl', S/'flow.tcl')
shutil.copy2(R/'README.md', S/'README.md')
shutil.copy2(B/'build.pds', S/'FPGA_GSV1_M3_02.pds')
shutil.copy2(B/'build.pds', R/'FPGA_GSV1_M3_02.pds')
(S/'reports').mkdir(); (S/'docs').mkdir()
shutil.copy2(R/'reports/M2_01_edid.bin', S/'reports/M2_01_edid.bin')
documents = [('docs/M3_02_board_test.md', 'USER_TEST.md'),
             ('docs/M3_02_changes.md', 'CHANGES.md'), ('docs/M3_02_protocol.md', 'PROTOCOL.md'),
             ('reports/M3_02_delivery.md', 'DELIVERY.md')]
for source, name in documents:
    shutil.copy2(R/source, D/name); shutil.copy2(R/source, S/source)
    if name == 'DELIVERY.md':
        (D/name).write_text(report.replace('../docs/M3_02_board_test.md', 'USER_TEST.md'), encoding='utf-8')
shutil.copy2(R/'docs/M3_01_protocol.md', S/'docs/M3_01_protocol.md')
shutil.copy2(R/'docs/M3_01_protocol.md', D/'M3_01_protocol.md')
shutil.copy2(R/'docs/开发指挥与反馈约定.md', S/'docs/开发指挥与反馈约定.md')
shutil.copy2(R/'reports/M3_02_build_metrics.json', D/'build_metrics.json')
shutil.copy2(R/'reports/M3_02_bindings.json', D/'bindings_check.json')
shutil.copy2(B/'synthesize/apm_drm_lutram_utilization.log', D/'memory_mapping.log')
record = dict(Version=b['Version'], Bitstream=str(bit.resolve()), SHA256=b['SHA256'],
    GeneratedUtc=instant.isoformat(), GeneratedShanghai=shanghai.isoformat(),
    Build=str(B), Verification=audit, BuildPass=True, ConsumedInputsUnchanged=True,
    Programmed=False, BoardVerified=False, ExternalIoTimingSignoff=False,
    MeasuredHardwareFps=None, Metrics=metrics)
put(D/'release.json', record)
print(json.dumps(record, ensure_ascii=False, indent=2))
