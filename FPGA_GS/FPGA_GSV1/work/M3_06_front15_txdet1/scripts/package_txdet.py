"""One-shot package of the deterministic-PHY controlled integration candidate."""
from pathlib import Path
import datetime,hashlib,json,shutil,zipfile,re
R=Path(__file__).resolve().parents[1]
P=R.parents[1]
B=R/'build/M3_06_3_5_5_TXDET1_20261023_141332_459'
D=P/'release/FPGA_GSV1_M3_06_3_5_5_TXDET1_CANDIDATE'
assert not D.exists(),'Never overwrite a release'
def h(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def copy(a,b):
    b.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(a,b)
result=json.loads((B/'result.json').read_text(encoding='utf-8-sig'))
sta=json.loads((R/'reports/full_timing_summary.json').read_text())
assert result['BuildPass'] and result['InputsUnchanged'] and sta['declared_constraints_met']
assert sta['output_setup_min_ns']>0 and sta['output_hold_min_ns']>0 and len(sta['output_DO_paths'])==80
assert json.loads((R/'reports/txdet_checks/result.json').read_text())['checks']['tx']
assert 'TXDET_PHY_PASS' in (R/'reports/txdet_checks/phy.log').read_text(encoding='utf-8-sig')
manifest=json.loads((B/'inputs.json').read_text(encoding='utf-8-sig'))
for item in manifest:
    assert h(Path(item['Source']))==item['SHA256'].lower()
    assert h(B/item['RelativePath'])==item['SnapshotSHA256'].lower()
D.mkdir()
name='FPGA_GSV1_M3_06_3_5_5_TXDET1_CANDIDATE_HDMI_1080P60.sbit'
bit=Path(result['Release']);copy(bit,D/name)
assert h(D/name)==result['SHA256'].lower()
for item in manifest: copy(B/item['RelativePath'],D/'source'/item['RelativePath'])
for f in ['build_txdet.ps1','check_txobs.py','configure_m36_endpoints.py']:
    copy(R/'scripts'/f,D/'source/scripts'/f)
for f in ['m364_tx_tb.sv','m364_burst_tb.sv','m364_clock_model.sv','m36_line_ram_model.sv','m361_phy_model.vh','txdet_phy_tb.sv']:
    copy(R/'sim'/f,D/'source/sim'/f)
for f in ['result.json','inputs.json','pds_console.log','report_timing/fpga_gsv1_top.rtr','place_route/fpga_gsv1_top.prr','place_route/clock_utilization.txt']:
    if (B/f).exists(): copy(B/f,D/'evidence/build'/f)
for f in ['implementation_notes.md','source_changes.json','txobs1_source_manifest.json','register_sources.json','local_summary.json','full_timing_summary.json',
          'txdet_checks/result.json','txdet_checks/inputs.json','txdet_checks/tx.log','txdet_checks/tx_compile.log','txdet_checks/phy.log',
          'local_io_final/flow.tcl','local_io_final/local_io.v','local_io_final/local_io.fdc','local_io_final/output_window.json','local_io_final/local_console.log','local_io_final/report_timing/local_io.rtr',
          'full_output_paths/query.tcl','full_output_paths/console.log','full_output_paths/report_timing/fpga_gsv1_top.rtr',
          'drive24_characterization/io_model24.json']:
    copy(R/'reports'/f,D/'evidence'/f)
artifact=dict(version='M3-06 3.5.5 TXDET1',classification='controlled_integration_candidate_pending_board',
    bitstream=str(D/name),sha256=h(D/name),generated_utc=result['GeneratedTime'],
    generated_Asia_Shanghai=datetime.datetime.fromisoformat(re.sub(r'(\.\d{6})\d+',r'\1',result['GeneratedTime'].replace('Z','+00:00'))).astimezone(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
    build_pass=True,declared_STA_pass=True,internal_STA_pass=True,nominal_PHY_TX_model_pass=True,external_PHY_PVT_PCB_signed_off=False,
    PHY_force_TX_RX_delay=True,PHY_delay_nominal_ns=2,FPGA_TXC_relative_data_nominal_ns=0,TX_data_control_drive_mA=12,TXC_drive_mA=16,
    local_TX_setup_ns=.070,local_TX_hold_ns=.096,full_TX_setup_ns=sta['output_setup_min_ns'],full_TX_hold_ns=sta['output_hold_min_ns'],
    nominal_sampling_delay_window_ns=sta['nominal_PHY_delay_window_ns'],resources=sta['resources'],
    source_scope_files=[x['file'] for x in json.loads((R/'reports/source_changes.json').read_text())],
    programmed_by_agent=False,board_verified=False,front_15fps_60s_pass=None,build_directory=str(B),
    restore_TXOBS1=str(P/'release/FPGA_GSV1_M3_06_3_5_4_TXOBS1/FPGA_GSV1_M3_06_3_5_4_TXOBS1_HDMI_1080P60.sbit'),
    original_service_preserved=True,new_diagnostic_entrypoints=False)
(D/'artifact.json').write_text(json.dumps(artifact,ensure_ascii=False,indent=2),encoding='utf-8')
readme=f"""# M3-06 3.5.5 TXDET1 受控整机候选

尚未下载上板，不是已验收的稳定修复版。唯一推荐文件：
{name}

SHA256：{h(D/name)}
实际生成：{artifact['generated_Asia_Shanghai']}
构建：一次完整候选构建。旧TXOBS1/E1/3.5.4及失败TXP2全部保留。

## 修了什么、为什么

网口2不再依赖未知strap与两个PLL输出的外部相位组合。TXC和TXD/TX_CTL共用原PLL OUT0/同一全局时钟、名义同沿输出；PHY寄存器明确覆盖为TX/RX内部延时都开启，TX名义2ns。RX逻辑、原PLL参数、网口1及所有视频/业务协议源码不改。

PHY按Linux/U-Boot实际位定义读改写，只修改延时控制掩码；保留其他位。读回、正常页恢复及页读回确认成功后才ready；任何失败保持无效并重试，硬件复位后重新配置。现场原值8575时目标回读BD75。旧Linux注释的TX/RX位名矛盾已列出；此次两位均置1，位名冲突不改变选定行为。

始终驱动的GTP_OUTBUF替代恒定使能OUTBUFT，去除非业务所需的三态路径，真实DO不屏蔽。实际布线IO设置：TXD/TX_CTL 12mA FAST，TXC16mA FAST，保持LVCMOS33/3.3V。24mA局部模型离散没有更好，不采用。

## 实际验证

- PHY：ID扫描、保留位、读改写、强制TX/RX延时、读回失败拒绝、页恢复失败拒绝、MDIO失败恢复、PHY硬件复位后重配、ready不提前有效均通过。
- 生产路径引脚重组：ARP2、连续控制10、前摄长包8，12220字节；FCS、首末字节/载荷、19次IFG均通过，最短IFG466字节时间。必要PLL/断链复位恢复通过。
- 局部真实PNR：setup+0.070ns、hold+0.096ns。
- 整机实际PNR：80条TX真实DO覆盖五个数据/控制引脚、双发射/捕获沿、慢/快角；最差setup+0.070ns、hold+0.096ns，无TO路径或负裕量。
- 内部STA慢角setup最小+0.462ns、hold+0.202ns；快角setup+1.834ns、hold+0.118ns；recovery/removal均非负。
- 声明模型下公共总采样偏移窗口[1.930,2.096]ns，名义2ns位于其中。
- 实际FF19856、LUT19260、CLMA3838/6450、CLMS2475/4250、DRM94/134、PLL5/5。
- 未重跑HDMI、摄像头、滤镜、FILE_TEST、算法和香橙派历史测试。没有安装依赖、修改网络、服务、缓冲或协议。

## 时序边界必须保留

接收器setup/hold各1ns未降低。捕获点显式为实际TXC理想4ns加PHY内部名义2ns；物理时钟路径只计算一次，双沿均约束，无输出multicycle或false path。

工具实际报告PLL相关不确定度0.05ns；最初自行增加的0.1ns没有器件或测量依据，不把它冒充真实抖动。它与接收器1ns要求明确区分，剩余slack公开作为预算。根时钟0.2ns原设置未改，不能说工具已将它全量用在相关生成钟间。

**PHY内部名义2ns的PVT上下界、PCB偏斜与实际负载边沿未获保证，不能将声明模型通过写成完整板级签核。** RX外部窗口及基线未覆盖的边界也未在本轮新增签核。局部margin不大，15fps稳定性必须实测。

日志“hold fix failed”针对原0.35ns优化目标；已单独检查最终STA实际非负余量及零失败端点。没有删真实DO路径制造通过。完整证据见evidence/implementation_notes.md和evidence/full_timing_summary.json。

## 最短板测

1. 保持原服务、15fps、8MiB缓冲、接线、端口、供电及配置。只下载本目录唯一候选sbit，不固化Flash。
2. 回复“TXDET1已下载，串口保持连接”。开发端复用现有collect_freeze.ps1和read_net2_diag.ps1，同步10秒。
3. 正常：自动ARP、online=true、完整CAM0彩色画面连续更新，完整帧率接近15fps，组帧丢弃/socket drops/ethtool硬件CRC均零增量。串口延时回读应为BD75（掩码内3800），GMII坏帧为0，无PLL/ready反复下降。
4. 短窗正常直接连续做一次60秒；只在60秒也达标后报告本次15fps质量验收通过。ethtool窗口包围业务主窗且含命令开销，分别注明边界。
5. 异常：不继续长窗，不换线、不配IP、不冷启动、不重启服务。保留本次已有配置回读/GMII/主机同窗结果，恢复下列TXOBS1：

{artifact['restore_TXOBS1']}

本轮不要先启动网口1或重复视频功能验证；前摄闭环通过后再抽查网口1/显示。现有双击入口仍在：
{P/'orangepi/oneclick/启动前摄预览.cmd'}
{P/'orangepi/oneclick/检查FPGA通信.cmd'}
服务已运行时不要重复启动；本轮采样由开发端复用已有入口，无新增同功能诊断工具。

## 回传摘要

3.5.5 TXDET1确定延时整机候选已生成；TXC与数据共用OUT0、PHY强制TX/RX内部延时、RMW/读回/页恢复失败门控ready。仅四个网口2生产文件改变。生产ARP/控制/长包FCS及PHY异常恢复通过；一次整机构建及声明模型STA通过，TX最小setup+0.070ns/hold+0.096ns。尚未板测，PHY延时PVT/PCB未完整签核。下一步只下载本候选，按10秒→60秒真实15fps质量验收；失败恢复TXOBS1。
"""
(D/'README.md').write_text(readme,encoding='utf-8')
for item in manifest: assert h(D/'source'/item['RelativePath'])==item['SnapshotSHA256'].lower()
sums=[h(p)+'  '+p.relative_to(D).as_posix() for p in sorted(D.rglob('*')) if p.is_file()]
(D/'SHA256SUMS.txt').write_text('\n'.join(sums)+'\n')
Z=D.with_suffix('.zip');assert not Z.exists()
with zipfile.ZipFile(Z,'x',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(D.rglob('*')):
        if p.is_file():z.write(p,p.relative_to(D.parent))
Z.with_suffix('.zip.sha256').write_text(h(Z)+'  '+Z.name+'\n')
print(json.dumps(artifact,ensure_ascii=False,indent=2))
