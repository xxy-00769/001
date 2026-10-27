"""Preserve a failed M3-05 attempt, without publishing a programming image."""
from pathlib import Path
import argparse,datetime,hashlib,json,re,shutil,zipfile
R=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--build',required=True);a=p.parse_args();B=Path(a.build).resolve()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def put(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2),encoding='utf8')
b=read(B/'result.json')
assert b['Version']=='M3-05 3.4' and not b['BuildPass']
assert b['InputsUnchanged'], 'A changed source snapshot must not be presented as the current build'
for v in read(B/'inputs.json'):
 assert sha(Path(v['Source']))==v['SHA256'].upper()
 assert sha(B/v['RelativePath'])==v['SnapshotSHA256'].upper()
checks={}
for name,pattern in [('camera','sim_m34_camera_*'),('hdmi','sim_m34_hdmi_*'),('status','sim_m34_status_*'),('scope','check_m34_scope_*')]:
 for d in sorted((R/'reports').glob(pattern),reverse=True):
  try:
   q=read(d/'result.json');assert q['Verdict']=='PASS' and q['InputsUnchanged']
   assert all(sha(Path(f))==h.upper() for f,h in read(d/'inputs.json').items())
   checks[name]=d;break
  except (AssertionError,FileNotFoundError):pass
 assert name in checks,name
timing=(B/'report_timing/fpga_gsv1_top.rtr').read_text()
assert 'Design Summary : Some Constraints Violated.' in timing
mins={};sections={}
for corner in ['Slow','Fast']:
 for kind in ['Setup','Hold','Recovery','Removal']:
  section=kind+' Summary('+corner+' Corner):'
  block=timing.split(section,1)[1].split('====',1)[0]
  vals=[float(m[1]) for line in block.splitlines() if (m:=re.search(r'([-+]?\d+\.\d+)\s+[-+]?\d+\.\d+\s+\d+\s+\d+\s*$',line))]
  mins[section]=min(vals) if vals else None
  if kind in ['Setup','Hold'] and corner=='Slow':sections[kind]=block
dmr=(B/'device_map/fpga_gsv1_top.dmr').read_text();prr=(B/'place_route/fpga_gsv1_top.prr').read_text()
def metric(t,n):return float(re.search(r'\|\s*'+re.escape(n)+r'\s*\|\s*([\d.]+)',t)[1])
metrics={n:metric(dmr,n) for n in ['FF','LUT','DRM','APM','PLL']}
metrics.update(CLMA=metric(prr,'Use of CLMA'),CLMS=metric(prr,'Use of CLMS'))
metrics['CLBPercent']=(metrics['CLMA']+metrics['CLMS'])*100/10700
now=datetime.datetime.now(datetime.timezone.utc)
D=R/'deliverables'/('FPGA_GSV1_M3_05_3_4_WIP_NO_BIT_'+now.strftime('%Y%m%d_%H%M%S'));D.mkdir(parents=True)
meta=dict(Version='M3-05 3.4 WIP',Released=False,BuildPass=False,STA=False,Programmed=False,
 BoardMeasured=False,RecommendedBitstream=None,PackagedUtc=now.isoformat(),Build=str(B),
 Resources=metrics,MinSlackNs=mins,Checks={n:str(d) for n,d in checks.items()},
 ScopeResult=read(checks['scope']/'result.json'),ExternalInputBudgetIsAssumption=True,
 HardwareHdmiFirstFailureConfirmed=False,HardwareRearGreenRootCauseConfirmed=False)
put(D/'status.json',meta)
report=f'''# M3-05 3.4 未放行报告

**本轮没有完成可烧录3.4交付。** 最终候选已修改，定向数字检查通过，实际综合/布局布线完成，但真实约束STA失败，未将生成的原始文件放入release，也没有唯一推荐新位流。没有烧录、Flash固化或修改电脑配置；3.3旧包保留。

## 实际改动与确认边界

HDMI RGB/HS/VS/DE统一IO首级寄存后参与几何判定；新增L0～L7分阶段诊断，已通过逐拍2拍OSD对齐检查。摄像头打包不改字节顺序，像素÷2改为同字节时钟树的下降沿分频，并恢复与PCLK的相关时序检查。详见[修改与证据](../docs/M3_05_changes.md)。不裁边、不涂黑、不加重滤镜、不调曝光或盲改接收寄存器。

已确认原约束将相关摄像头时钟错误分异步组。恢复检查的首轮后摄数据交接hold −5.503ns，说明此前存在签核遗漏。地址检查确认右摄第三槽0x2400000与前摄0x2000000、后摄及HDMI槽不重叠。最终网络RTL、DDR仲裁、所有权、滤镜/显示流水及电脑工具未改；帧缓存只增加被动观测端口。

**尚未确认现场HDMI首个失败环节，未确认绿点唯一根因，未证明已恢复左摄或后摄画质。** 没有板卡观测，不能把输入采样候选或仿真通过当成板上定位。L码尚未供用户烧录验证，因为本候选STA未放行。

原外部输入没有delay预算。本轮额外采用“边沿前后各1ns稳定”的工程假设；它不是MS7200/OV5640资料保证，也不是实测。该假设下失败不能直接证明现场输入出错。预算保留，未通过移除/放宽它或切断相关路径来宣称通过；实际输入契约仍需有依据的时序预算或物理观测。

## 已实际检查

| 检查 | 结果及范围 |
|---|---|
| 摄像头 | PASS：生产输入寄存、字节打包/分频，完整720行、921600像素，720组首末像素，交替行相位，独立RGB565期望。 |
| HDMI | PASS：输入→监测→capture_pipe，完整1650×750/1280×720；60和59.94Hz、非法行总量、丢VS；9216000有效像素、8个正确完整帧判定、2拍tuple及后级同步。 |
| 诊断 | PASS：8种状态及恢复、8个可区分码，每拍坐标变化时OSD像素/区域2拍对齐。 |
| 范围/地址 | PASS：144个未改文件哈希；除输入采样外顶层接线、帧缓存及处理流水等价，帧地址无重叠。 |
| 综合/布局布线 | 实际运行完成；STA未通过，不能交付烧录。 |

没有重跑网络软件回环、已通过滤镜穷举或历史整机长跑。3.3用户15fps短窗发送14.37/发布14.27/显示14.31/前摄4.98fps为既有实测，不冒充3.4数据。实物HDMI、后摄绿点和3.4性能均未测。

## 最终实际资源与时序

- FF {metrics['FF']:g}，LUT {metrics['LUT']:g}，DRM {metrics['DRM']:g}/134，APM {metrics['APM']:g}，PLL {metrics['PLL']:g}/5；CLMA {metrics['CLMA']:g}，CLMS {metrics['CLMS']:g}，CLB {metrics['CLBPercent']:.2f}%。
- 各角最坏裕量（ns）：`{json.dumps(mins,ensure_ascii=False)}`。
- 构建：`{B}`；入口：`pwsh -NoProfile -File scripts/build_m34.ps1`。
- STA摘要：`Design Summary : Some Constraints Violated.`；完整逐路径报告随源码包提供。
- 标准输出目标保留1920×1080p60、148.5MHz、2200×1125、+HS/+VS、AVI VIC16；没有改成30Hz。

### Setup慢角
```text
{sections['Setup'].strip()}
```
### Hold慢角
```text
{sections['Hold'].strip()}
```

## 交付与下一步

本次仅保存**不含位流的候选源码/检查/失败证据包**：`{D}`，打包UTC时间{now.isoformat()}。新推荐位流路径、生成时间和SHA256：**无（STA失败，未发布）**。build目录的原始.sbit不推荐烧录，也不能称为合格3.4。旧3.3位流未替换。

尚需解决输入采样与实际输入契约的时序闭合，再运行受影响的定向检查及真实STA。不可把未证实的±1ns假设当作现场根因，不重复不可布局的IMDDR/不可布线的本地IDDR候选，不继续网口2、30fps或M4。

用户本轮无需换接线、改分辨率或重复15fps/历史验收。只有得到STA通过的唯一推荐文件后，才按[最短验收](../docs/M3_05_board_test.md)执行：KEY6原图看左摄单/四格→后摄边缘→右摄保持15fps→快速滤镜切换；预期真实左摄恢复、绿点消失、右摄流畅。当前不能要求用户烧录失败产物来完成这些确认。

```text
回传指挥：M3-05 3.4未完成交付。已改HDMI完整tuple IO寄存/分阶段L码、摄像头相关时钟÷2交接及约束；完整720行像素/HDMI60与59.94/OSD对齐/地址隔离定向检查PASS。网络15fps相关RTL和电脑工具未改。最终构建实际综合布线完成，但STA未通过；未发布新位流、未烧录、旧3.3保留。现场HDMI首失败环节和绿点根因仍未确认；±1ns输入预算仅工程假设，不能当作实物证据。暂停30fps/网口2/M4。
```
'''
(R/'reports/M3_05_delivery.md').write_text(report,encoding='utf8')
shutil.copy2(R/'reports/M3_05_delivery.md',D/'M3_05_delivery.md')
S=D/'source';S.mkdir()
for folder in ['rtl','vendor','constraints','config']:shutil.copytree(B/folder,S/folder)
for folder in ['scripts','sim','docs','tools']:
 shutil.copytree(R/folder,S/folder,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
shutil.copy2(B/'flow.tcl',S/'flow.tcl')
for name,d in checks.items():
 dest=D/'evidence'/name;dest.mkdir(parents=True)
 for f in d.iterdir():
  if f.suffix in ['.json','.log']:shutil.copy2(f,dest/f.name)
for f in ['inputs.json','result.json','pds_console.log','device_map/fpga_gsv1_top.dmr','place_route/fpga_gsv1_top.prr','report_timing/fpga_gsv1_top.rtr']:
 dest=D/'build_evidence'/f;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(B/f,dest)
for d in (R/'reports/M3_05_baseline').glob('io_probe*'):
 dest=D/'rejected_candidates'/d.name;dest.mkdir(parents=True)
 for f in ['probe.v','probe.fdc','probe.tcl','console.log']:
  if (d/f).exists():shutil.copy2(d/f,dest/f)
for label,f in [('old33_io',R/'reports/M3_05_baseline/report_timing/fpga_gsv1_top.rtr'),('old32_io',R/'reports/M3_05_baseline/io32/report_timing/fpga_gsv1_top.rtr')]:
 shutil.copy2(f,D/(label+'.rtr'))
put(D/'files.sha256.json',{f.relative_to(D).as_posix():sha(f) for f in D.rglob('*') if f.is_file()})
assert not list(D.rglob('*.sbit'))
archive=Path(shutil.make_archive(str(D),'zip',D.parent,D.name))
with zipfile.ZipFile(archive) as z:assert z.testzip() is None;assert not any(n.endswith('.sbit') for n in z.namelist())
for f,h in read(D/'files.sha256.json').items():assert sha(D/f)==h
put(R/'reports/M3_05_wip_package.json',dict(Directory=str(D),Archive=str(archive),SHA256=sha(archive),NoBitstream=True))
print(json.dumps(dict(Directory=str(D),Archive=str(archive),SHA256=sha(archive),Resources=metrics,MinSlackNs=mins),ensure_ascii=False,indent=2))
