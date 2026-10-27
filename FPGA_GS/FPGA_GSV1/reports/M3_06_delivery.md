# M3-06 3.5 双网口分流交付

已完成实际修改、定向检查、综合、布局布线、真实STA及新位流。**未自动烧录，双网口硬件和实际帧率待用户验收。** HDMI问题已确认是接线，M3-05/05A撤销；基线是实际发布3.3，3.4未交付WIP保留隔离，后摄绿点仍独立未解决。

## 实际修改

- 网口1仅右摄VIDEO_IN及自身会话/心跳/遥测，目标保留用户已确认的15fps。网口2负责CAM0干净原彩色FRONT_RAW上传及KEY/RESULT/ACK/心跳，上传先5fps。两端独立MAC/IP/session/计数及PHY队列恢复，只有网口2更新判定。
- 原前摄网络读者迁往网口2，仍只有一个上传读者，保留三槽、显示/上传独立持有和中止排空。网口1RESULT不改反馈，网口2VIDEO_IN不写右摄DDR。
- 新增网口2 RTL8211E MDIO扫描、芯片ID核验、内部延时读改写/读回、千兆链路及停钟检测。PHY实际地址由运行时扫描确认，未冒称已经板上测得。
- 网口2自身RXC经IOCLKBUF/IDES4采样及IOCLKDIV二分频，每字两个GMII字节，经八字缓冲顺序送自身125MHz MAC。PLL仍5/5，不共用另一PHY采样时钟。
- 集中配置`config/m3_endpoints.json`，电脑工具增加right/front-control角色。front-control不创建右摄发送worker；保留真实视频、暂停循环、原尺寸前摄和模拟判定。

关键文件：`rtl/board/fpga_gsv1_top.v`、`rtl/network/m3_network.v`、`m3_net_core.v`、新增`m36_phy2.v`及`m36_rgmii_interface.v`、`constraints/mes50hp.fdc`、`config/m3_endpoints.json`和`tools/m3/console.py`。57个已有RTL逐字不变，包括HDMI、摄像头、滤镜、DDR仲裁、前摄所有权、MAC及右摄三槽。完整滤镜仍启用，未开发识别或30fps优化。

唯一对接契约：`E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/docs/M4_link_contract.md`。协议与3.3逐字一致：GSV3 v1，48字节头，每帧1440片×1280字节RGB565小端像素。KEY.frame_id是core接收本地事件时CAM0最近完整帧；5fps上传不保证已上传该帧，缺证据必须UNKNOWN。详细修改见发布包`source/docs/M3_06_changes.md`。

## 实际检查与边界

完整尺寸组合PASS：四路1280×720，两个生产MAC、独立网络时钟（第二口相位独立且+200ppm）、共享生产DDR仲裁、CAM0独立上传和1080p60生产显示路径。右摄15fps两完整帧；田字格/单右摄两个完整输出帧，独立source/frame/row/col期望值核对4147200像素；前摄完整1440片。覆盖包积压、DDR合法停顿、SOF/请求CDC相位、错误角色VIDEO拒绝、上传中途网口2断链后的DDR排空释放及另一口继续。

PHY定向PASS：101个MDIO事务，错误ID扫描、保留位、读回、仅千兆就绪、停钟恢复及复位。角色/控制PASS：独立端点和会话、错端口拒绝、KEY帧绑定、旧RESULT拒绝、TTL及PHY队列epoch。未改文件以哈希核对，复用本轮已执行日志；历史IMDDR功能日志已明确作废，由最终IDES4结果替代。

最终RGMII功能检查PASS：4096字节逐字匹配、首末拍及缓冲反复回绕，使用厂商SERDES/IOCLKDIV模型和不同本地/全局时钟插入。主机角色检查PASS：默认速率、HELLO角色、不创建无用发送worker、right不能RESULT、协议未变。主机socket使用mock，仅验证分工；未重复软件回环。

组合仿真使用同接口/延迟RAM模型加速，算法旁路并保持显示流水；实际生产构建保留完整滤镜及DRM行存储。物理PHY/DDR电气、两口真实性能及断链现场恢复尚未测试，不能将仿真或请求fps当板端测量。

## 构建、资源和真实STA

构建入口：候选`./scripts/build_m36.ps1`。实际构建目录：
`E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/work/M3_06_3_5/build/M3_06_3_5_20261021_205634_277`

退出码0，冻结输入哈希未改变，完整滤镜启用。发布工程`source/FPGA_GSV1_M3_06.pds`的136个源码/IP引用均存在；清除了本机旧构建输出缓存引用，保留实际构建选项。

| 项目 | 3.3 | 3.5 |
|---|---:|---:|
| FF | 15470 | 18729 |
| 映射LUT | 14969 | 18442 |
| 布线LUT | 14982 | 18460 |
| DRM | 89/134 | 94/134 |
| CLB | 44.89% | 56.17% |
| PLL | 5/5 | 5/5 |
| APM | 6.5 | 6.5 |

CLMA3652、CLMS2358。输出仍为1080p60、148.5MHz、2200×1125、正HS/VS、VIC16，输入仍720p。新增MAC125MHz、采样字时钟62.5MHz。

最终真实STA为All Constraints Met：最小setup +0.197ns、hold +0.028ns、recovery +1.379ns、removal +0.325ns。新端口输入双沿1.2～2.8ns、时钟不确定度0.2ns；物理输入延时15是实际IO设置，不是放宽时序。派生/父时钟在同一异步组，相关62.5/125MHz路径仍参与STA。

**网口2输入hold余量只有28ps，未含PCB偏斜；外部TX/PHY/板级电气未完整签核。构建和STA通过不等于双口硬件已验收。** 失败的全局直接采样、不可布线的IMDDR方案以及遗漏派生路径的异步分组均未发布，证据保留在候选构建目录。

## 唯一新位流

- 版本：M3-06 3.5。
- 绝对路径：`E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/release/FPGA_GSV1_M3_06_3_5/FPGA_GSV1_M3_06_3_5_DUAL_ETH_HDMI_1080P60.sbit`
- 生成时间：2026-10-21 21:03:44.803381 +08:00（Asia/Shanghai）；UTC 13:03:44.803381。
- SHA256：`760A6077FAB0AC19E4351DC51E1185F4C1FA6D5CAEC930BFEC539460A3FEB332`。
- 发布目录包含source、evidence、release.json及source_sha256.json；旧发布包未覆盖。工程入口为本发布source内`FPGA_GSV1_M3_06.pds`，根RTL仍有WIP，不当作本版入口。
- 3.4 WIP：`E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/deliverables/FPGA_GSV1_M3_05_3_4_WIP_NO_BIT_20261021_104224.zip`，SHA256 `96A4E006846CE6D507EF18998073EEE745E01A74DB740B450C9B709849B2F6A4`。

## 手工网络与准确命令

网口1为离HDMI较远的RJ45：电脑192.168.50.1/24，板192.168.50.2。网口2靠HDMI-OUT：香橙派或USB千兆网卡192.168.60.1/24，板192.168.60.2。两条直连不设网关、UDP双方50000、MTU1500。只读检查确认原电脑网卡已有192.168.50.1/24，未见192.168.60.0/24冲突；未修改网卡、路由、防火墙或安装依赖。只有一个电脑网卡可逐口检查，再接真实香橙派组合联调。

从发布source运行，两个角色分别开终端：

```powershell
cd E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/release/FPGA_GSV1_M3_06_3_5/source
python tools/m3/console.py --role right --right-fps 15
python tools/m3/console.py --role front-control --front-fps 5 --auto allow
```

真实视频在right命令后加`--video "实际视频文件绝对路径" --loop`，或GUI选择视频。工具留电脑主屏，HDMI扩展屏继续独立输出左摄。沿用既有Python/Pillow/tkinter/FFmpeg。

香橙派可在用户复制的source目录运行同一协议模拟工具，不代表识别程序：

```bash
python3 tools/m3/console.py --role front-control --bind 192.168.60.1 --board 192.168.60.2 --front-fps 5 --auto unknown --headless --seconds 70 --stats front_control_70s.json
```

识别任务只读使用冻结契约/协议，按原独立任务开发。完整说明见`source/docs/M3_06_board_test.md`。

## 最短一次板测

1. 用户烧录唯一位流，原HDMI/摄像头接线不变，接两条网线并启动角色，等千兆协商。KEY5到右摄应连续更新。统计分列请求、电脑发送、板端完整发布、显示新帧率，目标约15fps；隐藏右摄时显示新帧0正常。持续CRC/溢出/组帧错误或冻结为失败。
2. 网口2应见前摄完整干净彩色，接收目标约5fps，可勾选1280×720原尺寸。KEY5视角/KEY6滤镜只改变板上显示；上传仍CAM0原彩色。上传随视角改变或变灰为失败。
3. KEY1～3本地LED立即左/右/直；网口2收到唯一EVENT及模拟RESULT_ACK，板上显示允许。可改拒绝/未知/红灯/实线模拟；KEY4停车优先，按住再按KEY1～3应准确提示且不新增被忽略动作事件。长按不连发，旧回包不能盖新动作。
4. 拔网口2：上传停、判定按TTL回UNKNOWN，网口1右摄及本地LED继续；重插恢复。拔网口1：网口2前摄和控制继续；重插右摄恢复。拔一条导致另一条复位/冻结为失败。

记录两端统计JSON及同窗实际发送/发布/显示/前摄接收率。本版未上板，尚不能声称已保住两口同时15/5fps。后摄绿点未处理；30fps、识别和Flash固化未开展。

## 回传指挥摘要

M3-06 3.5已基于实际3.3发布源码完成双口分流并生成新位流；3.4 WIP隔离、HDMI修复撤销，HDMI/摄像头/滤镜未改。网口1右摄15fps目标，网口2前摄5fps及KEY/RESULT，单上传读者、独立会话/复位保留。契约docs/M4_link_contract.md已固定，协议与3.3逐字一致。完整720行双MAC/DDR/1080p组合及定向检查PASS，实际PNR/STA PASS：setup+0.197ns、hold+0.028ns；FF18729、DRM94、CLB56.17%、PLL5/5。新位流路径和SHA见本报告。未自动烧录，双口15/5fps、断链隔离及外部IO/PCB余量待实测；后摄绿点仍独立未解决。
