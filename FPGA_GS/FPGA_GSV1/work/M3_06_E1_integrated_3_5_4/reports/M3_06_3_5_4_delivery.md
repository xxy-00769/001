# M3-06 3.5.4 E1完整工程集成候选

已实际修改、完成生产网络定向检查、完成一次完整PNR/STA并生成新位流。**待上板，尚未确认整机网口2闭环恢复。** 不自动下载、不写Flash。E1成功基准与所有旧发布包均可回退。

## 唯一推荐候选

- 版本：M3-06 3.5.4，E1完整功能集成候选，滤镜启用。
- 位流：`E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/release/FPGA_GSV1_M3_06_3_5_4/FPGA_GSV1_M3_06_3_5_4_HDMI_1080P60.sbit`
- 生成时间：2026-10-22 **19:01:45 +08:00**（UTC 11:01:45）。
- SHA256：`324bcb33ac2dfaa888b7ed3d385668abf5f25a66e06712aefb88b7750b4adf48`。

## 刚改了什么

成功E1的证据已冻结到`release/FPGA_GSV1_NET2_BASELINE_E1_ACCEPTED_20261022.zip`，逐文件指纹见`evidence/E1_FROZEN_BASELINE.json`。同板同线E1的自动ARP和CRC零增量证据沿用，不要求用户重复E1。

完整工程以发布3.5.2的源码快照为基线（承接3.3的网口1右摄15fps），不使用3.4 WIP或旧3.5.3 TX实验结构。硬件实现仅7个文件有新增/变化，其余142个硬件文件一致，逐项哈希见`evidence/checks/baseline_delta.json`。

|关键文件|实际变化|
|---|---|
|`rtl/network/m364_e1_rgmii.v`|E1已实测IO实现，仅模块重命名；原厂IDDR/ODDR/OUTBUFT和半字节顺序保持|
|`rtl/network/m3_network.v`|网口2使用自身RXC、独立E1 PLL和E1 IO；增加与E1一致的GMII寄存器边界；复用生产MAC/协议/上传器；网口2硬件复位20ms|
|`rtl/network/m36_phy2.v`|增加strap只读模式，仍扫描PHY地址、校验ID和链路/时钟活动；不再强制写入内部RX/TX延时，不固定ready|
|`rtl/board/m364_ref_dividers.v`、顶层|板上50MHz精确分频为配置10MHz、相机参考25MHz，经显式全局缓冲，释放原配置PLL给网口2|
|`constraints/mes50hp.fdc`、`flow.tcl`|登记实际分频时钟、网口2独立PLL与新增RTL；不把旧RGMII-ID外部延时模型叠加到E1|

生产MAC、IP/UDP与KEY/RESULT协议、CAM0独立网络读者/帧所有权、DDR仲裁、HDMI视频逻辑、摄像头采样和滤镜源码均保留。移除本候选中已完成使命的大ARP串口捕获实例；协议内基本状态仍在，宿主检查读取真实硬件CRC。没有改香橙派算法，没有增加30fps或网口2之外功能。

E1资料来源、逐项差异、资源选择和边界详见`evidence/e1_integration_analysis.md`。E1通过不能证明某个差异是唯一根因；本轮选择迁移整组成功的PHY/时钟/IO关系，不继续优化旧失败TX。

## 时钟方案与实际构建结果

网口2独立RXC→原E1 PLL（VCO625MHz），输出0/1均125MHz。最终Clock Summary确认相位4ns/5ns，TXC比数据时钟晚1ns；不依赖网口1插线。PHY先硬复位载入strap，MDIO不写延时，避免E1外部移相与旧强制内部延时叠加。

配置/相机PLL的空输出不能保持另一个RXC的E1关系；HDMI PLL的1485MHz VCO不能同时整数精确分出10/25MHz。因此仅用50MHz的/5、/2释放配置PLL。配置10MHz占空比40/60、相机25MHz占空比50/50。HDMI与DDR PLL参数均未修改。小型真实PNR提前确认五PLL和分频全局缓冲的路由合法性，没有关闭专用路由检查。

整机工具自动落点：网口2PLL_158_55、HDMI PLL_158_75、网口1PLL_158_303、DDR PLL_158_199/179。实际位置与小型预检/E1不完全相同，不能声称物理布局完全复制E1；最终整机专用时钟路径合法，频率/相位关系与E1一致。

工具：PDS2022.2-SP6.4，PGL50H -6 FBG484，Production快/慢角。一次完整compile→synthesis→map→PNR→STA→bitstream完成，退出码0，RTL构建期间哈希不变。没有第二次完整构建。

|检查|实际结果|
|---|---|
|已声明约束STA|All Constraints Met；setup/hold、recovery/removal和最小脉宽均无已声明路径违例|
|全机最差setup/hold|+0.198ns / +0.116ns|
|网口2 125MHz域，慢角setup/hold|+0.558ns / +0.332ns|
|网口2 125MHz域，快角setup/hold|+2.645ns / +0.261ns|
|配置10MHz慢角setup/hold|+94.645ns / +0.342ns|
|相机25MHz慢角setup/hold|+36.732ns / +0.428ns|
|FF / LUT|18,756 / 18,439|
|CLMA / CLMS|3,678 / 2,336，合计6,014/10,700，约56.2%|
|DRM / PLL|94/134、5/5|

**覆盖限制：**网口2PHY输入眼宽、strap模式有效外部采样窗口和PCB相对偏斜仍未完成保证性签核；表65的要求未被当作任意可删预算，旧ID模型不能冒充E1模型。STA还保留38个历史相机I2C派生clock pin无时钟警告，与3.5.2相同；两路I2C原逻辑未改。25MHz参考和计数器本身已约束；一次补充同路由STA未成功纳入新增派生钟，未计为验证通过，原始尝试留证。All Constraints Met仅指已声明约束，不代表全部IO或全部内部路径覆盖。未因此扩大全板整改；本包为公开这些边界的受控集成板测候选。

## 本轮实际检查

1. 生产管理器→E1 RX→生产MAC/core→上传器→生产TX DRM/MAC→E1输出原语→TXC双沿引脚重组：2个ARP回复、10个控制回复、8个前摄长包通过。核对ARP地址/字段、独立期望彩色payload、首末字节、FCS及IFG；坏CRC被拒绝。
2. 连续负载：1个短帧、64个控制长度帧、8个前摄长度帧，共73帧、17,656字节，完整内容/FCS通过，最小IFG16个字节周期（要求≥12）。
3. 真实管理ready门控、PHY掉线/恢复、PLL失锁/恢复和队列异步断言/同步释放通过；strap延时寄存器未被写改。没有旁路CRC或固定ready。
4. /5、/2分频周期/占空比及5周期启动ready检查通过。小型路由预检及整机实际时钟表均核对。
5. Windows检查入口复用已修E1的scp+SSH字符流实现，stdout/stderr分离、退出码、完整BEGIN/END与结果字段校验保持；本机验证了缺计数/换会话为未知、静态邻居不算自动ARP、CRC增长不算通过。实际SSH、scp上传以及远端Python脚本`--help`执行通过，未安装依赖。

仿真不代表物理眼宽；PLL仿真波形仅用于逻辑检查。前摄长包检查使用既有DDR响应模型，不冒充完整摄像头/DDR视频重验。未重复视频算法、滤镜及历史全套；未下载候选，未获取3.5.4实物采样结果，真实5fps/15fps和断链恢复性能均待上板。启动服务和sudo完整采样由下面两个已整合入口完成。

## 用户只做三步

沿用原接线、IP、香橙派服务与网线，不重复E1，不安装软件。

1. **下载**上述唯一3.5.4位流到SRAM。等待约10秒，允许PHY重新协商。正常应恢复1080p60四路显示能力；不写Flash。
2. **双击启动**：`tools/启动前摄预览.cmd`。需要时输入现有SSH密码。复用现有LIVE_FRONT，前摄上传请求5fps，打开前摄Web预览。预览目标15fps不是实际上传fps。应看到online=true和持续更新的完整CAM0彩色图像；板上视角/滤镜不应改变上传来源和颜色。
3. **双击检查**：`tools/检查FPGA通信.cmd`。需要时输入SSH/sudo密码。工具通过scp上传独立Python到用户目录`~/fpga_gsv1_m364_tools/`，再SSH -t运行实际文件，采样10秒；没有嵌套Python源码。不改IP、路由、邻居或现有服务，不保存密码，主机密钥严格校验。

自动保存`tools/reports/M364_sample_时间.txt`及`.json`，窗口保留暂停。TXT显示以下五项，缺项为“未知”：

- 自动ARP：True，192.168.60.2解析为02:00:47:53:56:32，动态REACHABLE/STALE/DELAY/PROBE。PERMANENT不算通过。
- 心跳在线：True，同窗心跳接收为True。
- 同窗完整前摄帧数>0、实际接收fps；目标约5fps，实际值以报告为准，不以请求或预览fps代替。
- 硬件CRC增量=0，历史累计非零不影响本次增量判断。
- 全部闭环条件满足：True。

有完整`M364_SAMPLE_JSON_BEGIN/END`、但上述条件为False/未知，表示采样完成而闭环未通过；Python/SSH失败、缺完整JSON则明确显示“采样未完成”，不能作为硬件失败结论。正常Connection closed位于stderr附录，不覆盖JSON。

**失败时仅回传这一次TXT报告**（已含两次原始硬件/邻居/协议快照及错误信息），不要求换线、配IP或跑算法。成功后才抽查一次网口1右摄约15fps、KEY5视图、KEY6滤镜和显示；不重复完整历史验收。本轮先验收自动ARP→心跳→完整前摄→CRC零增量；KEY/RESULT真实判定联调留在闭环成功之后。

## 回传指挥摘要

3.5.4已将E1成功的独立RXC双相PLL、原厂IDDR/ODDR/IO、20ms硬复位和strap默认延时策略迁入完整生产工程；MAC/协议/前摄所有权和3.3网口1视频成果保留。50MHz精确分频释放配置PLL，HDMI/DDR PLL参数不变。生产短包/连续控制/前摄长包、FCS/IFG、掉线与PLL复位通过；首次完整PNR/已声明STA通过，网口2慢角setup/hold +0.558/+0.332ns，DRM94/134、PLL5/5。外部IO及历史I2C派生钟覆盖边界公开，候选尚未上板，不宣称网口2修复成功。用户下载→双击启动→双击检查，一次报告自动ARP、online、完整前摄帧/fps、CRC增量；E1和旧发布可回退。
