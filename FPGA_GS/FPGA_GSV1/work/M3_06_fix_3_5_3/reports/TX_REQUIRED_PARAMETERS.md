# 网口2TX：需要补齐的准确参数和工具模型

此文件不要求重新接线、设置IP、安装软件、运行算法或重新测量全部板级电气。不是给用户新增一轮通用诊断。生产RX已实物识别ARP，MAC发出完整正确ARP/FCS，继续沿用这些证据。

## RTL8211E资料确认

实际芯片ID为001C/C915。驱动访问page7、ext page A4、reg1C，将[13:11]写为111，现场读回BD75。已知bit13为force、bit12为TX延时、bit11为RX延时；本轮没有改写值。

需要厂家明确：

1. 在该模式下，以PHY外部TXC输入引脚为基准，TXD[3:0]/TX_CTL保证满足接收的**有符号setup/hold边界**是什么？需要含PVT条件，明确负setup/hold的含义。
2. Rev1.6图32及表65的TsetupR/TholdR各1ns，是延后时钟旁的接口眼宽条件，还是可直接加到理想内部采样器的裸setup/hold？目前不能未经确认把“内部延时2ns”与“内部触发器要求1ns”视为完整保证模型。
3. 若给出的方式为内部TXDLY的min/max，请同时说明它与表65如何换算。仅名义2ns不够；TskewR=1/1.8/2.6ns的PCB时钟skew说明不能直接替代TXDLY的PVT范围。

影响：在现暂用模型中，五脚双沿公共区间在理想PCB、名义2ns、覆盖RXC占空比后仍为[-0.121,-0.315]ns，交集为空。若真实有效引脚窗口不同，必须按正式要求重算；不是自行放宽1ns来通过。

## MES50HP板卡资料确认

只需网口2TXC C20以及TXD C22/E20/E22/F21、CTL F22的走线长度/叠层或厂家给出的**相对飞行时间差最小/最大值**。已检索到的网口板资料有原理图，没有对应网口底板PCB走线报告；其他核心/连接板PCB不能代替该网口线路。

影响：数据相对TXC飞行时间差[Bmin,Bmax]直接移动setup/hold边界；不知道它不等于取0，不能把自行增加的0.3ns写成已测板级结果。

## PDS模型确认（备选单沿结构）

工具：PDS2022.2-SP6.4，PGL50H -6 FBG484，Production模型。可复现夹具：

`E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/work/M3_06_fix_3_5_3/reports/tx_sdr250_edge_probe`

同一配置PLL的CLKOUT3=250MHz/0ns给数据OREGIS；CLKOUT4=250MHz/2ns给TXC二分频寄存器。数据和TXC反馈寄存器都只用posedge，TXC的两个极性均应来自CLKOUT4正沿。六个输出实际为OREGIS。CLKOUT4上显式定义4ns/{2,4}，TXC生成时钟指定`-edges {1 3 5}`、8ns/{2,6}。

然而report_timing第430行路径，TXC下降沿沿CLKOUT4下降沿、BUFG下降沿传到TXC OREGIS CLK_SYS。这与posedge二分频的实际源沿不一致。`divide_by 2`改为显式源沿、重新PNR后仍如此。PDS shell实际未暴露set_clock_sense/set_sense命令。

需要的不是删除下降路径，而是**在保留TXC OREGIS/PAD各输出极性延时、early/late及CPR的前提下，正确表达两个输出极性均由源时钟正沿触发的合法约束或工具修正**。先在该小夹具中验证完整路径，再决定是否集成；不需要整机重建来验证一条约束命令是否有效。

另需说明：若使用配置PLL的CLKOUT3/4移相，资料表4-9只明确CLKOUT1精调误差±50ps；300ps p-p period/cycle jitter不是两路相对相位误差的直接规格。需要两路相对相位误差界限或工具如何已包含它的说明，避免将同一项重复计入。

## 当前实施决定

当前OSER4双沿结构不再统一移相或调驱动。配置PLL直接转发方案没有改善窗口；专用IOCLK/EXT方案在实际固定PLL位置到C20非法。单沿方案物理放置合法，但捕获模型未完成，不将此结果写成通过，也不据此宣称所有PLL结构均不可行。

上述参数/模型补齐前没有合格3.5.3位流，不能要求用户用失败STA产物上板碰运气。已完成的生产发送功能检查继续沿用，不重复摄像头、HDMI、滤镜、DDR、网口1功能测试。
