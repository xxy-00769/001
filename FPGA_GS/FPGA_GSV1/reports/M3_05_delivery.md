# M3-05 3.4 未放行报告

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

- FF 15545，LUT 15100，DRM 89/134，APM 6.5，PLL 5/5；CLMA 2932，CLMS 1858，CLB 44.77%。
- 各角最坏裕量（ns）：`{"Setup Summary(Slow Corner):": 0.486, "Hold Summary(Slow Corner):": -4.569, "Recovery Summary(Slow Corner):": 4.753, "Removal Summary(Slow Corner):": 0.468, "Setup Summary(Fast Corner):": 1.834, "Hold Summary(Fast Corner):": -2.445, "Recovery Summary(Fast Corner):": 5.617, "Removal Summary(Fast Corner):": 0.323}`。
- 构建：`E:\zhoumian\FPGA\FPGA_GS\FPGA_GSV1\build\M3_05_3_4_20261021_183609_367`；入口：`pwsh -NoProfile -File scripts/build_m34.ps1`。
- STA摘要：`Design Summary : Some Constraints Violated.`；完整逐路径报告随源码包提供。
- 标准输出目标保留1920×1080p60、148.5MHz、2200×1125、+HS/+VS、AVI VIC16；没有改成30Hz。

### Setup慢角
```text
****************************************************************************************************
                                                                          TNS Failing      TNS Total
 Launch Clock           Capture Clock              WNS(ns)     TNS(ns)      Endpoints      Endpoints
----------------------------------------------------------------------------------------------------
 sys_clk                sys_clk                     12.995       0.000              0           1588
 ddrphy_clkin           ddrphy_clkin                 0.638       0.000              0          39852
 ioclk0                 ioclk0                       1.692       0.000              0             24
 ioclk1                 ioclk1                       1.692       0.000              0             72
 cmos1_pclk             cmos1_pclk                   3.653       0.000              0             76
 cmos2_pclk             cmos2_pclk                   4.134       0.000              0             76
 cmos1_pclk_16bit       cmos1_pclk_16bit            12.229       0.000              0           1462
 cmos1_pclk             cmos1_pclk_16bit             2.094       0.000              0            217
 cmos2_pclk_16bit       cmos2_pclk_16bit            17.895       0.000              0           1101
 cmos2_pclk             cmos2_pclk_16bit             1.664       0.000              0            217
 pix_clk                pix_clk                      0.486       0.000              0           3577
 cfg_clk                cfg_clk                     94.620       0.000              0           1101
 clk_25M                clk_25M                     36.697       0.000              0             31
 hdmi_rx_clk            hdmi_rx_clk                  4.435       0.000              0           1251
 eth_rxc|network/pll/u_pll_e3/CLKOUT1_Inferred
                        eth_rxc|network/pll/u_pll_e3/CLKOUT1_Inferred
                                                     6.778       0.000              0              2
 eth_rxc|network/pll/u_pll_e3/CLKOUT0_Inferred
                        eth_rxc|network/pll/u_pll_e3/CLKOUT0_Inferred
                                                     1.188       0.000              0           1367
```
### Hold慢角
```text
****************************************************************************************************
                                                                          THS Failing      THS Total
 Launch Clock           Capture Clock              WHS(ns)     THS(ns)      Endpoints      Endpoints
----------------------------------------------------------------------------------------------------
 sys_clk                sys_clk                      0.218       0.000              0           1588
 ddrphy_clkin           ddrphy_clkin                 0.201       0.000              0          39852
 ioclk0                 ioclk0                       0.450       0.000              0             24
 ioclk1                 ioclk1                       0.450       0.000              0             72
 cmos1_pclk             cmos1_pclk                  -3.731     -35.729             10             76
 cmos2_pclk             cmos2_pclk                  -4.569     -44.154             10             76
 cmos1_pclk_16bit       cmos1_pclk_16bit             0.302       0.000              0           1462
 cmos1_pclk             cmos1_pclk_16bit             4.379       0.000              0            217
 cmos2_pclk_16bit       cmos2_pclk_16bit             0.355       0.000              0           1101
 cmos2_pclk             cmos2_pclk_16bit             4.833       0.000              0            217
 pix_clk                pix_clk                      0.328       0.000              0           3577
 cfg_clk                cfg_clk                      0.322       0.000              0           1101
 clk_25M                clk_25M                      0.428       0.000              0             31
 hdmi_rx_clk            hdmi_rx_clk                 -3.752     -70.603             19           1251
 eth_rxc|network/pll/u_pll_e3/CLKOUT1_Inferred
                        eth_rxc|network/pll/u_pll_e3/CLKOUT1_Inferred
                                                     0.549       0.000              0              2
 eth_rxc|network/pll/u_pll_e3/CLKOUT0_Inferred
                        eth_rxc|network/pll/u_pll_e3/CLKOUT0_Inferred
                                                     0.342       0.000              0           1367
```

## 交付与下一步

本次仅保存**不含位流的候选源码/检查/失败证据包**：`E:\zhoumian\FPGA\FPGA_GS\FPGA_GSV1\deliverables\FPGA_GSV1_M3_05_3_4_WIP_NO_BIT_20261021_104224`，打包UTC时间2026-10-21T10:42:24.057833+00:00。新推荐位流路径、生成时间和SHA256：**无（STA失败，未发布）**。build目录的原始.sbit不推荐烧录，也不能称为合格3.4。旧3.3位流未替换。

尚需解决输入采样与实际输入契约的时序闭合，再运行受影响的定向检查及真实STA。不可把未证实的±1ns假设当作现场根因，不重复不可布局的IMDDR/不可布线的本地IDDR候选，不继续网口2、30fps或M4。

用户本轮无需换接线、改分辨率或重复15fps/历史验收。只有得到STA通过的唯一推荐文件后，才按[最短验收](../docs/M3_05_board_test.md)执行：KEY6原图看左摄单/四格→后摄边缘→右摄保持15fps→快速滤镜切换；预期真实左摄恢复、绿点消失、右摄流畅。当前不能要求用户烧录失败产物来完成这些确认。

```text
回传指挥：M3-05 3.4未完成交付。已改HDMI完整tuple IO寄存/分阶段L码、摄像头相关时钟÷2交接及约束；完整720行像素/HDMI60与59.94/OSD对齐/地址隔离定向检查PASS。网络15fps相关RTL和电脑工具未改。最终构建实际综合布线完成，但STA未通过；未发布新位流、未烧录、旧3.3保留。现场HDMI首失败环节和绿点根因仍未确认；±1ns输入预算仅工程假设，不能当作实物证据。暂停30fps/网口2/M4。
```
