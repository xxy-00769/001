# -*- coding: utf-8 -*-
"""Freeze 3.3 only after the actual routed build and scoped evidence pass."""
from pathlib import Path
import argparse, datetime, hashlib, json, re, shutil

R=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--build',required=True);a=p.parse_args()
B=Path(a.build).resolve()
def read(f): return json.loads(Path(f).read_text(encoding='utf-8-sig'))
def sha(f): return hashlib.sha256(Path(f).read_bytes()).hexdigest().upper()
def put(f,v): Path(f).write_text(json.dumps(v,ensure_ascii=False,indent=2),encoding='utf-8')
def exact(d):
    result=read(d/'result.json')
    assert result['Verdict']=='PASS' and result.get('InputsUnchanged'),(d,result)
    for f,h in read(d/'inputs.json').items(): assert sha(f)==h.upper(),(d,f)
    return result
def pick(pattern):
    for d in sorted((R/'reports').glob(pattern),reverse=True):
        try: exact(d);return d
        except (AssertionError,FileNotFoundError): pass
    raise AssertionError('No current PASS evidence: '+pattern)

b=read(B/'result.json')
assert b['Version']=='M3-04 3.3' and b['ProcessingEnable'] and b['BuildPass']
assert b['ExistingConstraintsMet'] and b['InputsUnchanged']
for item in read(B/'inputs.json'):
    assert sha(item['Source'])==item['SHA256'].upper(),item
    assert sha(B/item['RelativePath'])==item['SnapshotSHA256'].upper(),item
assert sha(b['Release'])==b['SHA256'].upper()
timing=(B/'report_timing/fpga_gsv1_top.rtr').read_text()
assert 'Design Summary : All Constraints Met.' in timing
mins={}
for section in ['Setup Summary(Slow Corner):','Hold Summary(Fast Corner):','Recovery Summary(Slow Corner):','Removal Summary(Fast Corner):']:
    block=timing.split(section,1)[1].split('====',1)[0]
    vals=[float(m[1]) for line in block.splitlines() if (m:=re.search(r'([-+]?\d+\.\d+)\s+[-+]?\d+\.\d+\s+\d+\s+\d+\s*$',line))]
    assert vals and min(vals)>=0,section
    mins[section]=min(vals)
checks={n:pick(pattern) for n,pattern in {
    'backlog':'sim_m33_backlog_*','owner':'sim_m33_owner_*','queue_epoch':'sim_m33_epoch_*','rate5':'sim_m33_rate_5_*',
    'rate15':'sim_m33_rate_15_*','full30':'sim_m33_full_30_*',
    'core':'sim_m32_core_*','cdc':'sim_m32_cdc_*','epoch':'sim_m32_epoch_*','host':'host_m31_final_*'}.items()}
assert read(checks['full30']/'result.json')['Frames']>=3
for name in ['rate5','rate15','full30']:
    d=checks[name]
    adapted=(d/'core_with_packet_model.v').read_text()
    original=(R/'rtl/network/m3_net_core.v').read_text().split('module m33_packet_ram(',1)[0]
    assert adapted.split('module m33_packet_ram(',1)[0]==original

# Old accepted display/algorithm evidence is reused only for identical inputs.
old=read(R/'release/FPGA_GSV1_M3_03_3_2/release.json')
for name in ['format','display','processing','osd','reader','hint']:
    d=Path(old['Verification'][name]['Directory']);exact(d);checks['unchanged_'+name]=d

# The historical unit runner hashed much more than each binary consumed.
scopes={
 'ram_mac':['rtl/network/m3_byte_ram.v','rtl/network/m3_mac.v','sim/m3_mac_tb.sv'],
 'owner':['rtl/frame/m3_front_owner.v','sim/m3_owner_tb.sv'],
 'upload':['rtl/network/m3_upload.v','sim/line_ram_model.sv','sim/m3_upload_tb.sv'],
 'control':['rtl/board/m3_keys.v','rtl/display/m3_view_select.v','rtl/display/m1_hint_cdc.v','rtl/display/m3_osd.v','rtl/display/m3_text.v','sim/m3_control_tb.sv'],
 'right_owner':['rtl/network/m3_right_store.v','rtl/display/m2_rd_buf.v','rtl/reuse/wr_rd_ctrl_top.v','rtl/reuse/wr_cmd_trans.v','rtl/reuse/wr_ctrl.v','rtl/reuse/rd_ctrl.v','sim/line_ram_model.sv','sim/m3_right_owner_tb.sv']}
unit=None
for d in sorted((R/'reports').glob('sim_m3_unit_*'),reverse=True):
    try:
        q=read(d/'result.json');assert q['Verdict']=='PASS' and set(q['SelectedCases'])==set(scopes)
        manifest=read(d/'inputs.json')
        for case,files in scopes.items():
            for f in files: assert sha(R/f)==manifest[str(R/f)].upper()
            assert '_PASS' in (d/(case+'_run.log')).read_text()
        unit=d;break
    except (AssertionError,KeyError,TypeError): pass
assert unit;checks['units']=unit

perf={}
for requested in [15,30]:
    for d in sorted((R/'reports').glob('host_m33_*'),reverse=True):
        try:
            q=read(d/'result.json')
            if q.get('RequestedRightFps')!=requested: continue
            assert q['Verdict']=='PASS' and q['SoftwareLoopbackOnly'] and not q['BoardMeasured']
            assert q['Seconds']>=70 and q['FileLifecyclePass'] and q['OriginalPNGPass']
            perf[str(requested)]={'Report':str(d),'SoftwareLoopbackOnly':True,
                'ActualRightCompleteFps':q['ActualRightCompleteFps'],
                'ActualFrontReceiveFps':q['ActualFrontReceiveFps'],
                'WindowSeconds':q['Stats']['window_seconds'],
                'WindowPcSendFps':q['Stats']['window_pc_send_fps'],
                'Note':'Same sender/decoder implementation; measured before final GUI/counter-reset handling. Current host protocol regression passes.'}
            checks['software'+str(requested)]=d;break
        except (AssertionError,FileNotFoundError): pass
    assert str(requested) in perf

dmr=(B/'device_map/fpga_gsv1_top.dmr').read_text()
prr=(B/'place_route/fpga_gsv1_top.prr').read_text()
def metric(t,n): return float(re.search(r'\|\s*'+re.escape(n)+r'\s*\|\s*([\d.]+)',t)[1])
metrics={n:metric(dmr,n) for n in ['FF','LUT','DRM','APM','PLL']}
metrics['RoutedLUT']=sum(float(x) for x in re.findall(r'^\|\s+LUT\s+\|\s*([\d.]+)',prr,re.M))
metrics.update(CLMA=metric(prr,'Use of CLMA'),CLMS=metric(prr,'Use of CLMS'))
metrics['CLBPercent']=(metrics['CLMA']+metrics['CLMS'])*100/10700
assert metrics['DRM']==89 and metrics['PLL']==5
hierarchy=prr.split('Device Utilization Summary Of Each Module:',1)[1]
def hierarchy_row(n):
    return [line.split('|') for line in hierarchy.splitlines() if line.startswith('|') and line.split('|')[1].strip()==n]
cache=hierarchy_row('+ packet_cache');assert len(cache)==1 and float(cache[0][6])==8
assert len(hierarchy_row('+ m2_reader.hd.reader'))==3 and len(hierarchy_row('+ hd.reader'))==1
for n in ['+ row1','+ row2']:
    rows=hierarchy_row(n);assert len(rows)==1 and float(rows[0][6])==3
assert not hierarchy_row('+ sd.reader')

baseline=Path(old['Build']);changed=[]
for item in read(B/'inputs.json'):
    rel=item['RelativePath'].replace('\\','/')
    assert (baseline/rel).exists(),rel
    if sha(B/rel)!=sha(baseline/rel):changed.append(rel)
assert set(changed)=={'rtl/network/m3_mac.v','rtl/network/m3_net_core.v','rtl/network/m3_network.v','rtl/network/m3_right_store.v'},changed
addresses={'CAM0':[0,0x400000,0x2000000],'CAM1':[0x800000,0xc00000],
           'LEFT':[0x1000000,0x1400000],'RIGHT':[0x1800000,0x1c00000,0x2400000]}
regions=sorted((base,base+460800,source) for source,bases in addresses.items() for base in bases)
assert all(a[1]<=z[0] for a,z in zip(regions,regions[1:]));assert regions[-1][1]*4<256*1024*1024
for f in ['rtl/network/m3_net_core.v','rtl/network/m3_right_store.v']:assert "28'h2400000" in (B/f).read_text()
assert '.AVI_VIC(16)' in (B/'rtl/board/fpga_gsv1_top.v').read_text()
assert 'pix_clk                                        6.7340' in timing

D=R/'release/FPGA_GSV1_M3_04_3_3';assert not D.exists(),'Preserve previous releases'
D.mkdir();bit=D/'FPGA_GSV1_M3_04_3_3_NETWORK_FPS_HDMI_1080P60.sbit';shutil.copy2(b['Release'],bit)
utc=datetime.datetime.fromisoformat(re.sub(r'(\.\d{6})\d+',r'\1',b['GeneratedTime']).replace('Z','+00:00'))
cn=utc.astimezone(datetime.timezone(datetime.timedelta(hours=8)))
release=dict(Version='M3-04 3.3',Bitstream=str(bit),SHA256=sha(bit),GeneratedUtc=utc.isoformat(),
    GeneratedShanghai=cn.isoformat(),Build=str(B),BuildPass=True,ExistingConstraintsMet=True,
    Programmed=False,BoardMeasured=False,ExternalIoTimingSignoff=False,Resources=metrics,MinSlackNs=mins,
    ProductionChangedFiles=changed,AddressesNativeWords=addresses,FrameWords=460800,
    Verification={n:str(d) for n,d in checks.items()},SoftwarePerformance=perf,
    Hardware15FpsTargetMeasured=False,Hardware30FpsMeasured=False,
    Output=dict(Width=1920,Height=1080,Fps=60,PixelHz=148500000,HTotal=2200,VTotal=1125,VIC=16),
    PerfSimulationProcessingBypass=True,BuildProcessingEnable=True)
put(D/'release.json',release)
report=f'''# M3-04 3.3 交付

完成定向修复、数字检查、实际综合/布线/STA及冻结打包。**未烧录，板端15fps/30fps及运动改善待用户实测。** 用户已确认的3.2显示与真实视频输入保留，没有进入网口2/M4。

## 修改和确认的证据

仅改四个生产RTL：m3_mac（安全原因统计快照）、m3_net_core（FIFO消费、连续扫描及受校验约束的包DRM缓存、遥测）、m3_right_store（第三槽、保护、实际显示计数）、m3_network（接线和bank位宽）。电脑工具改善节奏并分开同窗四阶段fps。详情：[修改说明](../docs/M3_04_changes.md)。

旧MAC→core四槽积压复现分片0→3→1→2，写40拍/drop1；新顺序0→1→2→3，写160拍/drop0，均MAC溢出0。旧held+pending需等显示SOF也已复现；新增右摄0x2400000第三槽、20种SOF相位及引用断言验证有界申请。旧扫描+载荷重读至少53us/包，不够15fps；新每拍扫描并缓存，验证完才写DDR。旧首次构建setup −0.001ns未发布；统计使能加流水后通过真实STA，约束不变。

顺序FIFO恢复检查还复现PHY侧MAC单独复位后旧ACK/指针可能卡队列；新增双方异步置复位/本域同步释放，RX指针和ACK重置，同时排空已接受DDR写，未接受AW保持到完成。三个复位相位回归通过，控制会话/事件编号保持。电脑计数器回退时重新预热统计窗口，不把复位算成2^32个错误，也不清除事件去重。

尚未确认：现场1402个bad_packets组成、真实NIC线上突发及上述原因各自对板上掉帧的比例。不能把设计复现当成板上唯一根因。

## 实际检查

完整720行MAC→core→DDR速率检查：5fps两帧约4.99998fps、15fps三帧约14.99979fps，独立像素/行列/帧号校验，短突发/回绕和DDR数据等待，无持续掉帧。最终30fps组合检查日志随包，包含真实MAC、其他三路完整采写、前摄独立读者上传、高清生产读链/缩放/OSD、主机心跳、单路/四格/隐藏及重选，不以软件回环代替硬件链。组合短程结束早于板端500ms心跳/遥测周期，板端遥测输出和控制事件/重试另有core及单元检查，不将它们写成该组合检查已实际发包。

包RAM/缓存实际GTP原语、MAC FCS/溢出恢复和快照CDC、20种SOF相位/三槽保护、异常校验/会话/规格/片序/超时恢复、遥测64字节格式与字节序、控制重复/过期/重启、前摄1440片干净上传及CDC/旧返回排空均有PASS。未变的3.2显示/滤镜/PLL/OSD/行RAM检查以消费源码哈希复用，未重复调参。性能组合仿真算法旁路但匹配流水延迟，实际位流完整滤镜已综合、两行各3块DRM；DDR/包存储长跑用同延迟模型，另有原语实测仿真。物理PHY/DDR电气和板端性能未测。

电脑70秒双向软件回环：请求15fps实收完整约{perf['15']['ActualRightCompleteFps']:.3f}fps，同窗发送{perf['15']['WindowPcSendFps']:.3f}fps；请求30实收约{perf['30']['ActualRightCompleteFps']:.3f}fps，同窗发送{perf['30']['WindowPcSendFps']:.3f}fps；前摄约5fps，软件右摄无不完整帧。这里的模拟板端计数不是实物数据，30fps未达。主目标板端15fps（60秒发布≥约14fps）仍待实测。

## 构建和产物

- FF {metrics['FF']:g}（3.2为13817），映射LUT {metrics['LUT']:g}（14138）、布线LUT {metrics['RoutedLUT']:g}，DRM {metrics['DRM']:g}/134（81），APM {metrics['APM']:g}，PLL5/5。
- CLMA {metrics['CLMA']:g}，CLMS {metrics['CLMS']:g}，CLB {metrics['CLBPercent']:.2f}%（42.12%）。包缓存8 DRM，滤波两行6 DRM，四个高清读者均保留。
- 实际现有约束STA全部通过：setup {mins['Setup Summary(Slow Corner):']:+.3f}ns，hold {mins['Hold Summary(Fast Corner):']:+.3f}ns，recovery {mins['Recovery Summary(Slow Corner):']:+.3f}ns，removal {mins['Removal Summary(Fast Corner):']:+.3f}ns。外部IO延迟/电气未完整签核，未冒充实物测量。
- 输出标准1080p60，148.5MHz，2200×1125，+HS/+VS，AVI VIC16；源码/约束相对3.2仅上述网络四RTL改变。
- 新位流绝对路径：`{bit}`
- 版本：M3-04 3.3；生成：{cn.isoformat()}（UTC {utc.isoformat()}）。
- SHA256：`{sha(bit)}`
- 构建：`{B}`；工程：`{R/'FPGA_GSV1_M3_04.pds'}`。

## 用户测试和待办

按[用户测试](../docs/M3_04_board_test.md)接线/启动真实视频。先5fps，再15fps，各运行70秒、预热5秒后保存同窗约60秒JSON；15通过再试30。KEY5右摄或田字格保持可见，正常是实际发布/显示接近发送，运动更均匀、其他来源正常。只请求数上升、持续MAC溢出、发布仍近半、黑块/错源均失败。切走右摄时发布继续而显示新帧不增长属正常。KEY6五模式、前摄原图/PNG、KEY1～4/停车优先/模拟判定、暂停循环及断线恢复按表验收。

工具：`{R/'tools/m3/console.py'}`，准确命令在测试文档。未改网络配置、未安装依赖、未自动烧录/Flash。尚未完成板端15fps验收与30fps优化；旧3.2包保留。下一步回传5/15档JSON及运动观感，依据MAC/协议/组帧/等待原因增量处理剩余瓶颈，暂不进入网口2/M4。

```text
回传指挥：M3-04 3.3已修复并仿真复现验证RX槽固定优先乱序和显示帧槽等待；新增右摄三槽、校验后包DRM写入、原因统计及同窗发送/发布/显示/前摄fps。保持720p原图、1080p60和完整滤镜/前摄独立上传/控制。最终真实STA setup+{mins['Setup Summary(Slow Corner):']:.3f}ns/hold+{mins['Hold Summary(Fast Corner):']:.3f}ns，FF{metrics['FF']:g}/DRM{metrics['DRM']:g}/CLB{metrics['CLBPercent']:.2f}%。位流：{bit}；生成{cn.isoformat()}。软件15约14.44、30约27.87fps非板端数据；板端60秒15fps目标≥约14仍待用户测量，30未达，未烧录，未进入网口2/M4。
```
'''
(R/'reports/M3_04_delivery.md').write_text(report,encoding='utf-8')
shutil.copy2(B/'build.pds',R/'FPGA_GSV1_M3_04.pds')
readme=R/'README.md';text=readme.read_text(encoding='utf-8')
start=text.index('当前状态（');end=text.index('\n\n最新上板反馈',start)
text=text[:start]+'当前状态（2026-10-21）：M3-04 3.3完成网口右摄吞吐定向修复、生产MAC到DDR/显示检查、综合/布线/STA并冻结打包；未自动烧录，板端15/30fps与运动改善待实测。用户已确认3.2显示正常及真实视频进入右摄。网口2/M4暂停，保留旧包。'+text[end:]
text=text.replace('3.3尚未实施，网口2/M4未启动。','3.3已交付但板端性能待测，网口2/M4未启动。')
insert=f'''## 当前 M3-04 3.3 工程入口

位流：`release/FPGA_GSV1_M3_04_3_3/{bit.name}`；工程`FPGA_GSV1_M3_04.pds`。生成{cn.isoformat()}。[交付](reports/M3_04_delivery.md)、[修改](docs/M3_04_changes.md)、[准确命令和用户验收](docs/M3_04_board_test.md)、[遥测](docs/M3_04_protocol.md)。5/15fps完整720p收包仿真通过，30fps组合检查通过，实际STA setup+{mins['Setup Summary(Slow Corner):']:.3f}/hold+{mins['Hold Summary(Fast Corner):']:.3f}ns，DRM89、CLB{metrics['CLBPercent']:.2f}%。未宣称板端达标。

'''
text=text.replace('## 当前 M3-03 3.2 工程入口',insert+'## 历史 M3-03 3.2 工程入口')
readme.write_text(text,encoding='utf-8')
source=D/'source';source.mkdir()
for folder in ['rtl','vendor','constraints','config']:
    shutil.copytree(B/folder,source/folder)
for folder in ['tools','scripts','sim','docs']:
    shutil.copytree(R/folder,source/folder,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
for f in ['flow.tcl','README.md','FPGA_GSV1_M3_04.pds']:shutil.copy2(R/f,source/f)
for name,d in checks.items():
    dest=D/'evidence'/name;dest.mkdir(parents=True)
    for f in d.iterdir():
        if f.suffix in ['.json','.log'] or f.name=='core_with_packet_model.v':shutil.copy2(f,dest/f.name)
for f in ['report_timing/fpga_gsv1_top.rtr','place_route/fpga_gsv1_top.prr','device_map/fpga_gsv1_top.dmr','inputs.json','result.json','pds_console.log']:
    dest=D/'build_evidence'/f;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(B/f,dest)
shutil.copytree(R/'reports/M3_04_baseline',D/'baseline_reproduction',ignore=shutil.ignore_patterns('*.vvp'))
shutil.copytree(R/'reports/M3_04_epoch_baseline',D/'epoch_baseline_reproduction',ignore=shutil.ignore_patterns('*.vvp'))
shutil.copy2(R/'reports/M3_04_delivery.md',D/'M3_04_delivery.md')
put(D/'files.sha256.json',{str(f.relative_to(D)):sha(f) for f in D.rglob('*') if f.is_file()})
archive=shutil.make_archive(str(D),'zip',D.parent,D.name)
print(json.dumps(dict(Release=str(D),Bitstream=str(bit),SHA256=sha(bit),Archive=archive,Resources=metrics,MinSlackNs=mins),ensure_ascii=False,indent=2))
