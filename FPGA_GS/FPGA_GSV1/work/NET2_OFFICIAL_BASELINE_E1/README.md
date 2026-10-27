# 网口2官方结构基础收发实验 E1

**仅用于一次ARP/硬件CRC实物对照，不是3.5.3功能发布版，也不是板级时序签核。待上板。** 不包含DDR、摄像头、HDMI、滤镜、前摄上传、业务心跳或网口1业务。原完整工程、3.4 WIP和所有发布包均保留。

## 用户只做一次下载、一次采样

1. 保持香橙派eth0与FPGA网口2使用原网线，香橙派仍为192.168.60.1/24；Wi-Fi SSH保持原状。原LIVE_FRONT可以继续运行，不需要停止、重配网络或安装依赖。
2. 通过原下载工具，将包内`FPGA_GSV1_NET2_BASELINE_E1_EXPERIMENT_ONLY.sbit`下载到FPGA SRAM，不写Flash。等待约10秒，让千兆链路重新建立。
3. 在Windows双击包内`tools/采样网口2实验.cmd`。需要时输入现有SSH密码及香橙派sudo密码。约10秒采样自动完成，结果保存为同目录下`tools/reports/E1_sample_时间.txt`。回传**这一个TXT文件**即可。

入口沿用原oneclick里的SSH主机10.168.29.122、端口22、用户orangepi，不保存密码。脚本发送20个ARP探测，并读取硬件CRC、有效ARP和动态邻居；不删除/改写邻居，不更改IP/路由/防火墙，不占用现有50000监听端口。首次SSH信任或连接失效会明确报错，不跳过主机密钥验证。

本实验没有画面输出，HDMI无图、LIVE_FRONT online=false、无完整前摄是正常现象，不能据此判断实验失败；也不需要重复摄像头、滤镜验收。

## 应看到什么、如何判断

FPGA主动以10次/秒发送ARP request：谁是192.168.60.1；同时由官方ARP/MAC回应主机对192.168.60.2的ARP。FPGA MAC为02:00:47:53:56:32。官方ARP帧包含61字节MAC头/ARP/填充，再加4字节FCS；这高于Ethernet最小帧长，是合法长度，未为凑72字节改写官方MAC。

- `arp_roundtrip_baseline_pass=true`，收到探测回复、动态邻居正确，且`hardware_crc_delta=0`：本板网口2至少在E1实现下能正确收发。冻结E1的源码/位流/PLL/IO方案，再分析回整机的最小集成；不证明原整机已修复或外部全角落已签核。
- `tx_physical_baseline_pass=true`，收到有效周期ARP但回复/动态邻居未通过：网口2TX至少能发出主机接受的帧；进一步只查最小工程的RX/ARP闭环，不能说完全通过或重新泛查视频。
- `hardware_crc_delta>0`：官方网口2迁移结构下仍有线上CRC问题。仍不能直接判定板卡损坏；应在本工程范围核对PHY strap/IO/实际时序，必要时同一最小工程迁移网口1对照。
- 没有有效帧且CRC不增长：结果不确定，**不是通过**。计数缺失也标未知；软件收到ARP不能替代硬件CRC计数。
- 检出PERMANENT静态邻居不能算自动ARP通过；工具只报告，不自动修改。

## 官方来源及真实改动

官方源包：`E:/zhoumian/FPGA/资料/盘古50K开发板资料/盘古50K开发板/2_Demo/11_ethernet_test.rar`

SHA256：`2d2935bbf2840d56ba8422b1c9ee79b8b0582e08691135ed045ec890e29b7ed7`。`reports/origin.json`保存16个直接从RAR取出的原始成员及逐文件SHA；`reference/`保留原始内容。未整包复制历史构建产物，也未从3.4 WIP取模块。

官方默认网口1：RXC F14、TXC G16、RESET B20。原FDC还提供注释的网口2约束；与开发板硬件手册表3-2一致：RXC M19、RX_CTL B21、RXD[3:0] F18/D22/D21/B22，TXC C20、TX_CTL F22、TXD[3:0] F21/E22/E20/C22，RESET F19。保留官方4mA、FAST、LVCMOS33电气设置，不继承整机24mA试验。

官方针对板卡RTL8211系列PHY使用strap默认配置，没有MDIO事务或PHY延时写入。板卡资料及先前现场ID001C/C915对应RTL8211E；此实验本身不读取芯片ID/延时寄存器，不能把先前BD75说成E1配置。E1会用PHY硬件复位重新载入strap配置，默认TXDLY/RXDLY及内部PVT边界本轮未测。

保留原始`pll_phase.v`、`ref_clock.v`、ARP/MAC各模块。实际改动只有：

1. 新增精简顶层，去掉原UDP/IP/ICMP应用，仅保留ARP/MAC；MAC/IP改为现有60网段。沿用原eth_udp_test的GMII输入/输出寄存器级。
2. 顶层增加上电20ms PHY复位及两PLL锁定后的MAC三拍释放；10Hz ARP请求使TX验证不依赖RX成功，保留官方ARP回复路径。没有固定ready或关闭CRC。
3. 原`rgmii_interface.v`中`tx_reset_sync`未声明/未驱动，给它显式常0，与原数据ODDR的RST=0一致，依赖已有GRS初始化；没有修改ODDR/IDDR、半字节顺序、三态输出、采样边沿或PLL参数。
4. 启用官方网口2管脚并补充实际源时钟/内部时序约束，新增本实验采样工具。不修改原oneclick和香橙派程序。

## 时钟、构建与边界

PDS2022.2-SP6.4，PGL50H -6 FBG484，Production快/慢角。官方RX PLL为125/4×20=625MHz VCO，输出0/1均125MHz；实际STA Clock Summary为相对RXC相位4ns、5ns，两者差1ns。数据ODDR/接收IDDR使用输出0；TXC ODDR使用输出1，再经官方OUTBUFT输出。没有另加FPGA2ns或写PHY延时。

另保留官方50MHz参考PLL（VCO1000MHz），本精简工程只消费其lock，用于上电复位；未使用的200/125MHz输出被裁剪。实际PLL2/5、DRM0/134、FF720、LUT603、CLMA129、CLMS85。没有DDR控制器、视频或网口1硬件。

内部真实PNR/STA：慢角MAC setup +3.772ns/hold +0.321ns，50MHz域setup +15.352ns/hold +0.228ns；快角MAC setup +4.957ns/hold +0.258ns，50MHz域setup +16.581ns/hold +0.135ns。报告中的恢复/移除及最小脉宽均正裕量。没有内部同步违例，没有降低125MHz要求或增加内部假路径。

**外部限制：**原例程没有时序约束，本工程补了50MHz/125MHz源时钟和0.2ns内部不确定度。PHY RX输入延时、TX引脚级采样窗口和PCB skew没有建立有保证的外部约束；FDC明确声明这一点。报告`All Constraints Met`只针对这些已声明内部约束，不能解释成外部IO通过；没有拿去掉真实外部要求来发布合格功能版。按本轮授权，本实验允许在这些外部未知项公开的条件下做一次受控实物CRC对照。

`reports/sim.log`：生产官方ARP/MAC→原ODDR/OUTBUFT→实际TX引脚重组，3次ARP回复、2次周期ARP，共5帧，首末字节、地址、opcode、FCS及IFG通过。最小IFG375字节周期，超过12要求。注入请求经过原IDDR路径；测试明确假设PHY数据在未延时RXC后1ns变化，不是实测眼宽。仿真PLL输出由实际STA核实的时钟波形替代，仅为短包功能检查，PLL/路由结论来自真实PNR。`reports/independent_fcs.json`再以Python zlib独立核对五帧FCS。没有用功能仿真声称板级时序通过。

原样的生产RTL在首次构建后未修改；后续仅整理仿真/采样工具和文档。位流生成时间为北京时间2026-10-22 18:09:12，SHA及完整源码冻结见包内`artifact.json`和`SHA256SUMS.txt`。可在本独立工作目录执行`pds_shell.exe -f flow.tcl`重建，不依赖完整工程。
