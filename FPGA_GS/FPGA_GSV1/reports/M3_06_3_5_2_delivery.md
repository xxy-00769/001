# M3-06 3.5.2 ARP捕获诊断候选

**网口2功能修复尚未完成。本包只供一次有区分力的诊断，不是推荐的功能修复版；真实STA结果及位流信息附后。**

## 已确认事实和缺陷

- 用户网口2实测：香橙派硬件MMC在10秒内RX帧+10、总字节+640、CRC错误+10，好帧字节0，软件RX0。不能再解释成没有线上发送信号。同一香橙派、同一网线临时接FPGA网口1发10个ARP：RX帧+10、好帧字节+640、CRC零增量。故障已收窄到网口2特有TX路径，唯一物理根因尚未确认。不再要求重复该对照。
- 3.5.1原16条串口确认生产RX→桥→MAC→core正确接收ARP，ARP+15、TX请求及MAC包络+15，完成只+11，CRC/溢出/协议拒绝零。**确认的诊断错误**：m361_diag原来在dc域直接把nc域tx_ack用作变化计数条件，没有同步。core真实握手自身已有同步且一次仅一个未完成包；旧计数差不能当精确线上丢包数，无法据此反推真正完成总数。该诊断CDC错误不能认定为线上CRC失败根因。
- 发布3.5.1的303个manifest文件均匹配，位流SHA与原记录一致，根目录3.4 WIP完全隔离。网口2引脚与板卡表3-2及官方例程一致：TXC C20、CTL F22、TXD3..0 F21/E22/E20/C22。实际PHY ID001C/C915、延时BD75、状态ACC2，已核对延时位[13:11]以及TXDLY在PHY内部给TXC加名义2ns的含义。官方及网口1用PLL移相，网口2用自身RXC BUFG和PHY内部延时，这个差异本身不能认定为错误。

## 最小修改和验证

- `rtl/network/m361_diag.v`：在nc本域计完成数，再经已有握手快照跨域；被动捕获最近一个实际MAC输出的完整72字节ARP，含前导码/SFD、60字节以太帧及零填充、4字节FCS。N2 352串口每秒追加18个32位字。记录点是GMII，**不是物理引脚实测或板外抓包**。UART用固定4位移位代替除法/取模和宽可变选择，消除新增字符选择长路径。
- `rtl/network/m3_network.v`：仅给被动诊断连接现有txd，不反馈任何业务数据或握手。MAC、core、PHY管理、序列化和上传模块逐字节不变。
- `tools/m3/read_net2_diag.ps1`及`decode_net2_diag.py`：兼容351/352，独立zlib核对实际记录的FCS和ARP字段。原解码名称tx_pin_frames改为mac_tx_frames，明确它只计MAC包络，不能证明线上发包成功。
- `constraints/mes50hp.fdc`：新增传播至TXC引脚后加PHY名义2ns的capture时钟，rise/fall检查1ns setup/hold，指定不确定度0.2ns。未测PCB/PHY公差不由此签核。原六个TX引脚保持4mA/FAST，未改原引脚、输入预算或保护。没有固定ready、绕CRC或放宽约束。
- 曾做12mA内部探针，真实STA仍失败：TX setup -0.093ns、hold -0.185ns，另有新增UART和原网口1路径小负裕量。没有足够物理证据证明驱动增强能修复CRC，**已撤回该试改，不发布该探针位流**。未盲调PLL、相位、采样沿或PHY寄存器。
- `flow.tcl`仅将自动路由约束迭代上限3改1，避免无新增证据的相同IO预算重复路由，时序要求不变。新增定向仿真、冻结检查/打包和测试文档。

`scripts/check_m362.py`检查生产PHY管理、ready门控、同步TX RAM、MAC、ODDR/输出引脚重组；独立逐字核对完整ARP目的/源MAC、IP、操作码、字节顺序、首末字节、18字节零填充和FCS。ARP/HELLO各两次、坏CRC拒绝、链路恢复、完成计数跨域快照均通过。捕获记录独立CRC及UART实际115200 8N1整行40字/369字符通过。只加入固定非零偏斜，没有真实模拟IO模型，不能据此声称板级时序通过。

基线IO datasheet同极性输出差2～38ps不覆盖相反边沿或完整接收窗口，不能作通过依据；先前边沿对齐±0.5ns探针也不等于最终PHY内部采样模型，不能认作现场唯一根因。所有失败按实保留。

1080p60、HDMI、摄像头、滤镜、DDR、网口1右摄15fps、协议/业务端点、KEY/LED对应源码逐字节保留。未重复未受影响的全套视频、算法或软件回环。

## 唯一诊断实验及未完成项

此候选保持原发送电气设置，不预期仅靠计数修正就消除CRC。它用于一次分清运行时MAC实际报文与其后的发送段。若执行此次诊断，用户自行加载唯一ARP_CAPTURE_DIAG位流，恢复原两根网线，LIVE_FRONT保持。静态邻居已删除就不重复删除。不改IP、不停算法、不装工具、不再换线对照。

在Windows电脑PowerShell进入本包source，使用之前实际CP2102 COM号采5秒：

```powershell
& ./tools/m3/read_net2_diag.ps1 -Port COM7 -Seconds 5 -Output net2_diag_352.txt
```

COM7只是示例。回传net2_diag_352.txt即可。预期DA/targetMAC=00:00:a4:b5:5f:ef，SA/senderMAC=02:00:47:53:56:32，IP192.168.60.2→192.168.60.1，opcode2，zero_padding和fcs_valid均true。

- 没有记录：MAC未输出可捕获的完整ARP，继续定位运行时发送形成过程。
- 实际字段/FCS错误：继续查MAC/同步RAM/运行时逻辑，不调PHY相位。
- 记录完整正确且主机仍CRC错误：问题定位记录点之后的序列化/IO/PHY物理发送段；GMII记录不能证明引脚或线上字节正确。

最终目标仍是自动ARP解析→心跳online=true→完整CAM0彩色原图，统计真实接收fps；闭环恢复后才抽查一次网口1右摄15fps及显示滤镜，再联调KEY/RESULT。**上述闭环尚未恢复，实际PHY延时、PCB偏斜及波形未测。** 不进入30fps、网口2扩展或M4。

回传摘要：网口1同主机/同线10帧全好，网口2十帧全CRC错误，故障收窄至网口2特有TX。修正诊断完成计数CDC，3.5.2仅加完整实际ARP/FCS串口记录并撤回驱动试改；生产TX定向仿真通过，真实构建/STA结果见下。唯一诊断候选不是功能修复通过版。待5秒串口区分实际MAC报文错误与下游发送段错误，网口2闭环未完成。


## 实际构建、资源、唯一诊断位流

综合/布局布线/位流生成已完成。输入冻结哈希一致。**是否全约束STA通过：False；BuildPass=False。负裕量按失败保留，不能作为已签核修复版。**

资源相对3.5.1：FF 23865.0（原20889）、映射LUT 20864.0（原20027）、DRM 94.0/134（原94）、CLB 68.20%（原60.38%）、PLL 5.0/5、APM 6.5。

最终STA最小裕量ns：
```json
{
  "Setup Summary(Slow Corner):": -0.357,
  "Hold Summary(Slow Corner):": -0.449,
  "Recovery Summary(Slow Corner):": 1.933,
  "Removal Summary(Slow Corner):": 0.341,
  "Setup Summary(Fast Corner):": -0.005,
  "Hold Summary(Fast Corner):": -0.086,
  "Recovery Summary(Fast Corner):": 3.991,
  "Removal Summary(Fast Corner):": 0.27
}
```

网口2TX窗口slow setup/hold、fast setup/hold原始行：
```
eth2_rxc               eth2_phy_tx_capture         -0.357      -1.716              5              5
eth2_rxc               eth2_phy_tx_capture         -0.449      -2.134              5              5
eth2_rxc               eth2_phy_tx_capture         -0.005      -0.009              2              5
eth2_rxc               eth2_phy_tx_capture         -0.086      -0.319              5              5
```

完整原报告：evidence/build/report_timing/fpga_gsv1_top.rtr。名义PHY模型不等于实际波形测量。旧发布包保持不变，未自动烧录。

唯一诊断候选、真实时间和SHA256：
```json
{
  "Version": "M3-06 3.5.2 ARP capture DIAGNOSTIC ONLY",
  "Bitstream": "E:\\zhoumian\\FPGA\\FPGA_GS\\FPGA_GSV1\\release\\FPGA_GSV1_M3_06_3_5_2\\FPGA_GSV1_M3_06_3_5_2_NET2_ARP_CAPTURE_DIAG_HDMI_1080P60.sbit",
  "SHA256": "AA5B9B8752DB51579BEBFCA4D4422C53367CC1604EBA73D593B474326D2A04D6",
  "GeneratedUTC": "2026-10-22T07:13:28.520415+00:00",
  "GeneratedShanghai": "2026-10-22T15:13:28.520415+08:00",
  "Build": "E:\\zhoumian\\FPGA\\FPGA_GS\\FPGA_GSV1\\work\\M3_06_fix_3_5_2\\build\\M3_06_3_5_2_20261022_150437_235",
  "Resources": {
    "DRM": 94.0,
    "PLL": 5.0,
    "APM": 6.5,
    "CLMA": 4451.0,
    "CLMS": 2846.0,
    "FF": 23865.0,
    "MappedLUT": 20864.0,
    "CLBPercent": 68.19626168224299
  },
  "MinSlackNs": {
    "Setup Summary(Slow Corner):": -0.357,
    "Hold Summary(Slow Corner):": -0.449,
    "Recovery Summary(Slow Corner):": 1.933,
    "Removal Summary(Slow Corner):": 0.341,
    "Setup Summary(Fast Corner):": -0.005,
    "Hold Summary(Fast Corner):": -0.086,
    "Recovery Summary(Fast Corner):": 3.991,
    "Removal Summary(Fast Corner):": 0.27
  },
  "Port2CaptureRows": [
    "eth2_rxc               eth2_phy_tx_capture         -0.357      -1.716              5              5",
    "eth2_rxc               eth2_phy_tx_capture         -0.449      -2.134              5              5",
    "eth2_rxc               eth2_phy_tx_capture         -0.005      -0.009              2              5",
    "eth2_rxc               eth2_phy_tx_capture         -0.086      -0.319              5              5"
  ],
  "SynthesisRouteBitstreamComplete": true,
  "BuildPass": false,
  "STAAllConstraintsMet": false,
  "RecommendedFunctionalRelease": false,
  "BoardVerified": false,
  "PhysicalRootCauseConfirmed": false,
  "NetworkClosedLoopRestored": false,
  "TXPadDriveMilliamp": 4,
  "PHYRegistersOrPLLChanged": false,
  "ProtocolOrEndpointsChanged": false
}
```
