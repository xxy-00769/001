"""Preserve unsuccessful work; NEVER create a functional release from failed STA."""
from pathlib import Path
import datetime
import hashlib
import json
import re
import shutil
import zipfile

R = Path(__file__).resolve().parents[1]
ROOT = R.parents[1]
B = R/'build/M3_06_3_5_3_20261022_161139_183'
result = json.loads((B/'result.json').read_text(encoding='utf-8-sig'))
assert not result['BuildPass'] and not result['ExistingConstraintsMet']
assert result['InputsUnchanged'] and result['ExitCode']==0
for x in json.loads((B/'inputs.json').read_text(encoding='utf-8-sig')):
    assert hashlib.sha256((R/x['RelativePath']).read_bytes()).hexdigest()==x['SnapshotSHA256'].lower(),x
checks=json.loads((R/'reports/m363_checks/result.json').read_text())
assert checks['ProductionTX'] and checks['InputsUnchanged']
for p,h in json.loads((R/'reports/m363_checks/inputs.json').read_text()).items():
    assert hashlib.sha256((R/p).read_bytes()).hexdigest()==h,p
base=ROOT/'release/FPGA_GSV1_M3_06_3_5_2'
for p,h in json.loads((base/'source_sha256.json').read_text()).items():
    assert hashlib.sha256((base/'source'/p).read_bytes()).hexdigest()==h,p
assert hashlib.sha256(Path(json.loads((base/'release.json').read_text())['Bitstream']).read_bytes()).hexdigest().upper()==json.loads((base/'release.json').read_text())['SHA256']
log=(B/'pds_console.log').read_text(errors='replace')
def resource(name,first=False):
    v=re.findall(r'\|\s*'+re.escape(name)+r'\s*\|\s*([\d.]+)',log)
    assert v,name
    return float(v[0] if first else v[-1])
res={n:resource('Use of '+n) for n in ['CLMA','CLMS','DRM','PLL','APM']}
res.update(FF=resource('FF',True),MappedLUT=resource('LUT',True))
res['CLBPercent']=round(100*(res['CLMA']+res['CLMS'])/10700,3)
bit=B/'generate_bitstream/fpga_gsv1_top.sbit'
stamp=datetime.datetime.fromtimestamp(bit.stat().st_mtime,datetime.timezone.utc)
record=dict(Status='WIP / FAILED STA / NOT FOR PROGRAMMING',Version='M3-06 3.5.3 WIP',
            Build=result,InternalBuildArtifact=str(bit),
            InternalArtifactSHA256=hashlib.sha256(bit.read_bytes()).hexdigest().upper(),
            GeneratedUTC=stamp.isoformat(),GeneratedShanghai=stamp.astimezone(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
            Resources=res,ProductionTXChecks=checks,PublishedFunctionalBitstream=None,
            BoardVerified=False,PhysicalRootCauseConfirmed=False,
            CompleteARPAndVideoLoopRestored=False,BaselineManifestVerified=True)
(R/'reports/wip_record.json').write_text(json.dumps(record,indent=2))
report='''# M3-06 3.5.3 TX定向工作记录：未完成，未发布修复位流

当前不能交付功能修复候选：生产TX逻辑仿真通过，综合、布局布线和位流生成完成，但正确约束下的TX STA仍失败。内部构建产物仅留作复现证据，不应下载验收。没有用旧位流充当新版，也没有另发通用诊断版。

## 已确认事实与范围

独立解码3.5.2的六条现场完整72字节记录，ARP地址、opcode、补零、前导码/SFD和FCS全部正确；FCS实际/期望均0aa61877。MAC记录正确加上同主机/线网口1全好、网口2全CRC错误，将方向限定为记录点之后的TX。唯一现场物理根因仍未确认，不能把内部仿真或负裕量直接等同于实测根因。

已核对发布3.5.2 source manifest及位流SHA。工作隔离于work/M3_06_fix_3_5_3，不使用根目录3.4 WIP。硬件只改rtl/network/m36_rgmii_interface.v和constraints/mes50hp.fdc；145个其余硬件/config/vendor文件逐字一致，完整RX段逐字一致。PHY寄存器、MAC/core协议、HDMI、摄像头、滤镜、DDR、网口1保持源码一致。PLL仍5/5。

板卡表3-2和官方ethernet_test例程的网口2TX脚一致：TXC C20，CTL F22，TXD3..0 F21/E22/E20/C22。实际布线报告的端口/封装脚与其相符。RTL8211E ID001C/C915；BD75的[13:11]=111，page7/extA4/reg1C的TXDLY给TXC加入名义2ns，不是要求在FPGA内再叠加2ns。RX及该寄存器未改。官方和已实测网口1使用PLL移相ODDR，并不代表本轮24mA或OSER4来自官方设计。没有复制网口1或改变它。

3.5.1“TX请求/包络与完成不一致”的诊断CDC已在3.5.2修正；当前现场253→258全部一致。该旧计数差不是本轮CRC根因，未继续修改计数。

## 3.5.2负裕量的完整路径依据

reports/baseline_tx_paths.rtr保留132条完整路径及行号；baseline_windows.md/json列出五个数据/控制脚、slow/fast、setup/hold、PHY上升/下降沿共40个窗口。TXC传播全路径也包含在原报告中。

原路径：M19 RXC→输入PAD/INCK→BUFG USCM_84_108→全局125MHz→ODDR SYSCLK→PADO→输出PAD→封装脚。TXC也经过自己的ODDR和PAD，然后模型加入PHY内部2ns。仅看同极性各脚2～38ps相对差会漏掉早/晚、相反信号极性和输入时钟双沿传播差。

最差setup −0.357ns，TXD0下降跳变、PHY上升采样：

```
data = 5.560（late全局时钟）+.547（tco fall）+4.377（PAD fall）+.114（封装）=10.598
clock = 2（PHY名义）+5.226（early全局时钟）+.336（tco rise）+3.508（PAD rise）+.116=11.186
required =11.186+.305（CPR）−.250（不确定度）−1（setup）=10.241
slack =10.241−10.598=−.357
```

最差hold −0.449ns，CTL的TQ使能分析弧、PHY下降采样：

```
next data =8+5.226+.302（TQ tco）+3.508（PAD rise）+.078=17.114
clock =6+5.693+.547+4.377+.116=16.733
required =16.733−.420（CPR）+.250+1（hold）=17.563
slack =17.114−17.563=−.449
```

TI原本恒0；TQ路径出现在STA不等于现场使能真的在跳变。移除不必要的三态输出结构有明确结构依据，但不能说它已证实是CRC唯一根因。

## 实际修改及两次构建

1. 六个发送输出改固定GTP_OUTBUF；驱动4→24mA/FAST。原1ns setup/hold、PHY名义2ns均不变。capture指定uncertainty从.2收紧至.3ns（工具总计.35ns）。这个新增.1ns是设计公差预算，不是已实测PCB/PHY数据，也不代表板级电气签核。
2. 首次全局ODDR候选仍setup −.208、hold −.231ns，已明确判失败，不发布。
3. 改用已有rx_ioclk驱动OSER4，MAC保留125MHz；固定八字、每字两字节桥接到已有62.5MHz半频域。Gray指针同步并预填，四个数据脚按low0/high0/low1/high1发送，CTL为DV0/DV0/DV1/DV1，时钟0101。异步复位断言、半频域两拍释放，六个串行器共同复位。没有额外PLL，没有改RX实例或采样。
4. 第二次布局布线确认实际走SERCLK/CLK_IO：M19→INCK→IOCKGATE_326_322→IOCLK→OSER4→PAD；不是误用62.5MHz RCLK作为线速时钟。完整报告ioclk_first_tx_paths.rtr包含88条路径和所有40个双沿窗口。

第二次slow setup −.179、hold −.215ns；fast setup +.018、hold −.020ns。仍有违例，所以该候选也未发布。示例剩余setup路径：

```
TXD0: 4（falling launch）+2.814（late IO clock）+.426（tco rise）+3.621（PAD rise）+.114=10.975
TXC: 6（含PHY2ns）+2.426（early IO clock）+.259（tco fall）+2.980（PAD fall）+.116=11.781
required=11.781+.365−.350−1=10.796
slack=−.179
```

剩余hold示例：CTL next falling data=4+2.426+.259+2.980+.078=9.743；TXC rising capture=2+2.699+.426+3.621+.116=8.862；required=8.862−.254+.350+1=9.958；slack=−.215。数据/时钟均已进入IO clock，现阶段不能再归咎全局时钟树；剩余早/晚PAD及tco延迟压缩窗口。已有4/12/24mA报告也显示“驱动更大”不等于窗口单调改善。不继续重复相同调参。

尚无证明可同时满足双沿setup/hold的最终发送实现，不能靠统一挪动时钟解决同一采样沿上setup、hold同时为负的窗口。没有通过减小1ns要求、假路径、关闭CRC、固定ready或降低预算制造通过。暂未进一步改共享PLL或PHY寄存器，也未扩大到RX/视频整改。

## 实际验证及边界

- scripts/check_m363.py：生产网络管理/ready/reset→core→MAC真实同步TX DRM→双字节桥→厂商OSER4/OUTBUF→引脚重组。ARP2、控制10、前摄长包8，共12220字节；27个DDR返回burst，独立核对来源pattern、描述符、首末字节、完整FCS；19个IFG检查最小491字节时钟。坏CRC拒绝和链路恢复通过。
- 另一个生产MAC+TX RAM到相同发送引脚的连续负载：1短帧、64控制长度帧、8前摄长度帧，共73帧/17656字节，最小IFG16字节时钟，首末、padding、FCS全部通过。连续负载夹具初始reset未产生有效断言沿导致stream=X，已仅修正夹具为明确复位脉冲，没有据此改业务RTL。
- 前摄分片staging沿用既有sim/m36_line_ram_model.sv的一拍256→32契约模型；MAC TX RAM使用真实厂商DRM。vendor staging探针曾得到首像素0000，日志保留，不能宣称该模型边界已验证。前摄DDR/业务RTL未动，未扩大该排查。
- 功能夹具加入固定非零引脚差，只证明逻辑。真实电气结果采用布线后的生产模型STA，未以零偏斜仿真替代STA。
- 没有重跑不受影响的视频、滤镜、算法或软件回环；没有自动烧录或执行SSH。
- 已准备只读双击通信采样工具：同窗动态ARP、online、心跳、新完整前摄帧/fps、硬件mmc_rx_crc_error增量。缺失为未知、静态邻居不算自动ARP，session变化不误算fps；语法及这些判定夹具通过。未修改原启动入口/远端服务/算法。由于没有合格位流，本轮不要求用户运行它。

## 当前交付边界与下一步

本轮目标尚未完成。没有推荐新位流；内部生成文件/哈希仅为复现，不应用于用户下载验收。已发布3.5.2及旧包原样保留。

用户暂不需要换线、改IP、测网页或重复串口诊断。待TX实现通过正确STA后，才安排原定三步：下载→双击启动→双击通信检查；自动ARP、online、完整CAM0和硬件CRC零增量全部通过后，再抽查右摄15fps及显示滤镜。当前未新增任何板测通过声明。

需要继续解决的是具体TX双沿电气窗口，或取得能校准实际PCB/PHY公差的硬件依据；不能把尚未设计/验证的替代时钟结构写成可交付方案。

## 构建原始记录

```json
'''+json.dumps(record,indent=2)+ '\n```\n'
dest=ROOT/'reports/M3_06_3_5_3_TX_WIP_status.md'
dest.write_text(report,encoding='utf-8')
(R/'docs/M3_06_3_5_3_TX_WIP_status.md').write_text(report,encoding='utf-8')
archive=ROOT/'deliverables/M3_06_3_5_3_TX_WIP_NOT_FOR_PROGRAMMING.zip'
assert not archive.exists(),archive
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    z.writestr('README.md',report)
    for folder in ['rtl','vendor','constraints','config','sim','scripts','tools']:
        for p in (R/folder).rglob('*'):
            if p.is_file() and not any(x in p.parts for x in ['__pycache__']) and p.suffix not in ['.vvp','.pyc']:
                z.write(p,Path('source')/p.relative_to(R))
    z.write(R/'flow.tcl','source/flow.tcl')
    for p in (R/'reports').rglob('*'):
        if p.is_file() and p.suffix not in ['.vvp']:
            z.write(p,Path('evidence')/p.relative_to(R/'reports'))
    for n in ['result.json','inputs.json','report_timing/fpga_gsv1_top.rtr','pds_console.log','place_route/clock_utilization.txt']:
        z.write(B/n,Path('evidence/final_failed_build')/n)
    prior=R/'build/M3_06_3_5_3_20261022_154613_026'
    for n in ['result.json','report_timing/fpga_gsv1_top.rtr']:
        z.write(prior/n,Path('evidence/first_failed_build')/n)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert not any(n.lower().endswith(('.bit','.sbit')) for n in z.namelist())
(archive.with_suffix('.zip.sha256')).write_text(hashlib.sha256(archive.read_bytes()).hexdigest().upper()+'  '+archive.name+'\n')
print(json.dumps(dict(Report=str(dest),WIPArchive=str(archive),Resources=res,PublishedFunctionalBitstream=None),indent=2))
