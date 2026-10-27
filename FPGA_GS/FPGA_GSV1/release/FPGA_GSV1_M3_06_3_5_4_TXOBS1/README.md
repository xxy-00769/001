# 3.5.4 TXOBS1 被动观察实验（不是修复发布）

原3.5.4、E1及所有旧发布包保留。仅新增ODDR前生产GMII逐帧CRC检查，导出现有PHY诊断和PLL/ready下降计数；不改变协议、主机服务、PHY配置、PLL参数、IO驱动或业务模块。

生成：2026-10-23 12:15:24 +08:00。
位流：FPGA_GSV1_M3_06_3_5_4_TXOBS1_HDMI_1080P60.sbit。
SHA256：6ec610c1280f42d6ecf5a7e988d36c7b94a2febf139a219d94b6b7d2f365a4d2

## 最短操作

1. 保持香橙派原程序、网线、端口不变。接上此前使用的板载USB串口（CP2102），关闭占用串口的终端；FTDI COM29/30是下载器，不当作UART。
2. 用户手动下载本目录唯一.sbit，不固化Flash。回复“观察版已下载，串口已接”。随后由开发端复用tools/m3/read_net2_diag.ps1及现有orangepi/oneclick/collect_freeze.ps1同步采样，不需要启动新客户端或更改网络。
3. 先10秒定位。若CRC、组帧丢弃和socket drops均零，再采60秒真实15fps验收；若有错，按下列分支定位，不把实验构建通过当作修复。

## 判别

- GMII坏帧增加：检查ODDR前的MAC/RAM/边界时序，保留坏帧ID、长度及CRC余数。
- GMII无坏而主机硬件CRC增加：首个损坏区间位于此观察点之后，结合PHY寄存器、PLL/ready和实际布线路径缩小到序列化/IO/PHY/下游物理接收段，不能仅据此区分具体器件。
- PLL/ready下降或PHY状态异常：按对应事件定向修复。计数通过50MHz同步采样，不能覆盖任意短脉冲。
- CRC消失：不能宣称已找到根因。新增被动逻辑仍改变布局：data全局缓冲由USCM84_110变为84_109，负载由354变为690；TXC仍84_115。需对照真实路径及连续60秒质量。

## 验证与限制

新检查器7帧测试通过：正常短/长帧、故意载荷/FCS/截断/前导错误及恢复。生产发送路径通过ARP2、控制10、前摄长包8，核对实际引脚重组字节、FCS与IFG；观察帧计数一致且坏帧零。没有重跑视频、滤镜、算法或历史全套验证。

PNR及现有约束下的慢/快角setup/hold/recovery/removal通过，详见reports。网口2慢角setup+0.955ns、hold+0.286ns；快角setup+2.871ns、hold+0.201ns。内部通过不等于PHY/PCB外部采样窗口签核，沿用基线外部模型未知项，未放宽约束。硬件实测尚未进行。

UART115200 8N1，每秒前缀N2 35O（字母O），40个32bit十六进制字：W0 PHY ID；W1高16位延时寄存器原始值/低16位no_ack；W2 wrong_id/delay_fail；W3高16位status、低16位配置状态；W4 GMII总帧；W5坏帧；W6最近坏帧ID；W7余数；W8长度；W9 PLL下降；W10 ready下降；W11 bit1 PLL/bit0ready；W12..39保留。原始寄存器先按资料核对，不盲目解释或修改延时。

source为实际构建快照及相关脚本；reports保留定向验证及真实PNR/STA。原始完整构建位于work/M3_06_front15_txobs1/build/M3_06_3_5_4_TXOBS1_20261023_120634_068。
