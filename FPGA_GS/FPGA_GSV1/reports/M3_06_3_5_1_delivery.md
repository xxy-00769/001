# M3-06 3.5.1 网口2诊断候选交付

**尚未确认现场唯一根因，没有宣称网口2已经恢复。** 此次交付的是用户授权的最小被动诊断候选。网口2ready、CRC、PHY配置、采样边沿和数据通路没有盲改。

## 已确认的事实与缺口

- 原3.5发布294个源文件哈希全部匹配，147个冻结构建输入与发布源码一致，位流哈希与原记录一致。未发现源码/工程/位流错配。
- 网口2引脚、位序、方向与MES50HP官方表3-2一致，综合/布线产物包含G22的MDIO三态IOBUF及G20 MDC输出。MDIO帧格式、ID掩码、reg17状态位和page7/extA4/reg1C双延时配置与资料一致；这些核对不能替代真实PHY寄存器读值。
- **确认的验证缺口**：3.5完整组合仿真直接喂GMII，绕过PHY管理、生产ready/复位、IDES4桥。原独立PHY和接收桥单测也没有证明联合启动与引脚回包。这是验证缺陷，不是已经确认的硬件根因。
- 新生产链路仿真在原3.5上也能通过ARP/HELLO/FCS，仍未复现现场故障。PHY未配置/未ready、桥采样、MAC拒包、TX物理通路等仍是待板测假设；没有把任一候选写成结论。

## 实际修改

- m36_phy2.v只新增ID、延时回读、无ACK/ID/回读失败、状态/步骤/ready被动输出，原管理状态机不变。
- m3_mac.v只导出已有发布toggle；m3_net_core.v只新增ARP/HELLO接受计数，原解析/控制/发送行为不变。
- m3_network.v接出计数并仅为网口2实例化m361_diag.v；新增跨域握手快照、原始RX活动/桥/MAC/TX计数、115200串口每秒一行。
- 顶层只接板载CP2102 UART TX（R9），约束只追加该引脚，flow.tcl加入诊断源。KEY/LED无变化。提供只读串口采集与解码工具。
- 其余RTL和vendor与发布3.5逐字节一致；HDMI、摄像头、滤镜、DDR、右摄存储、前摄读者、协议和端点未改；根目录3.4 WIP未使用、未删除。

## 实际验证/构建

`python -X utf8 scripts/check_m361.py`通过：生产PHY管理→nr/queue门控→IDES4桥→真实DRM MAC→core→真实OSERDES TX引脚，ARP/HELLO各两次、坏FCS拒绝、ready阻断下原始活动可见、恢复后正常收发。串口整行207字符、22字十六进制、115200对应8N1序列单测通过。独立源码范围检查确认PHY/MAC/core原功能代码未变。

仿真缩短启动计数及管理轮询，保留生产复位释放/门控。固定时钟插入模型不包含PCB、真实PHY及物理输入延时，因此不能证明板上收发。未重跑未受影响的视频、滤镜、算法或软件网络回环。

构建入口`& ./scripts/build_m36.ps1`，综合/布局布线/STA通过，冻结输入未变；原约束保留，未固定ready、绕过CRC、放宽约束。没有自动烧录。

首个诊断探针版本在RX_CTL到晚到达的全局125MHz时钟寄存器路径上产生-3.309ns违例，已停止且未发布。最终仅把被动包络观察改为50MHz三级CDC，未动真实接收采样或约束；失败与修正证据保存在evidence/probe_sta_failure/。这不是现场根因证据。

| 项 | 原3.5 | 本版 |
|---|---:|---:|
| FF | 18729 | 20889 |
| 映射LUT | 18442 | 20027 |
| DRM | 94/134 | 94/134 |
| CLB | 56.17% | 60.38% |
| PLL | 5/5 | 5/5 |

各角最差裕量ns：`{"Setup Summary(Slow Corner):": 0.175, "Hold Summary(Slow Corner):": 0.028, "Recovery Summary(Slow Corner):": 1.807, "Removal Summary(Slow Corner):": 0.489, "Setup Summary(Fast Corner):": 0.692, "Hold Summary(Fast Corner):": 0.088, "Recovery Summary(Fast Corner):": 3.939, "Removal Summary(Fast Corner):": 0.319}`。All Constraints Met只表示现有约束通过；原RGMII外部电气/PCB偏斜未签核的边界仍保留，不能当作显示或网口实物验收。

## 唯一候选文件

- 位流：`E:\zhoumian\FPGA\FPGA_GS\FPGA_GSV1\release\FPGA_GSV1_M3_06_3_5_1\FPGA_GSV1_M3_06_3_5_1_NET2_DIAG_HDMI_1080P60.sbit`
- 版本：M3-06 3.5.1 NET2 DIAG（诊断候选）
- 生成时间（北京时间）：2026-10-22T13:37:57.170424+08:00
- SHA256：`51C9986B555DB819EDEA679D44D9C4CD1AADA3B8F068E71609D12A69F14F63A2`
- 冻结源码、实际工程、构建/检查证据：同发布目录source/、evidence/。

## 用户最短测试

1. 自行加载上述位流，沿用接线，网口2靠HDMI-OUT。香橙派执行一次`sudo ip neigh del 192.168.60.2 dev eth0`，保留LIVE_FRONT运行。5秒后自动邻居应为02:00:47:53:56:32且不是INCOMPLETE/FAILED/PERMANENT，eth0 RX应增加。
2. Web应online=true、心跳/分片/完整CAM0彩色帧增加、实时前摄可见。记录10秒实际接收fps。未测得帧率前不宣称达到5fps。
3. 若仍失败，板卡USB串口Type-C接电脑，115200 8N1无流控；执行source目录下`& ./tools/m3/read_net2_diag.ps1 -Port COM7 -Seconds 15 -Output net2_diag.txt`（替换实际COM号）。只需回传15秒日志、一次邻居/eth0统计、Web诊断截图及实际文件SHA/网口位置。不再重复网络配置或历史验证。
4. 闭环恢复后仅抽查一次网口1右摄15fps与显示/滤镜。KEY/RESULT留到前摄完整原图恢复后。

详细字段、正常/失败判据和无依赖命令见source/docs/M3_06_3_5_1_net2_test.md。一次日志可区分PHY/ready、原始RX、桥、MAC CRC/包槽、ARP/HELLO与TX启动/完成；原始活动计数不能证明FPGA正确收包，TX计数也不能证明香橙派物理收到。

## 遗留与回传摘要

网口2真实ARP→心跳→完整前摄闭环**未完成板测**，本版也没有已证实的数据通路修复。需要上述一次板上快照定位第一个失败环节，再进行有证据的局部修复。没有进入KEY/RESULT、30fps、网口2以外功能或M4算法。

可复制回传：M3-06 3.5.1已交付NET2被动诊断候选，基线为发布3.5，3.4 WIP隔离保留；确认原组合仿真绕过真实PHY/ready/桥，新引脚级ARP/HELLO/CRC/门控恢复及串口检查通过，构建/STA通过。未确认现场根因、未宣称恢复。请加载唯一NET2_DIAG位流，删除临时静态邻居；若不通，回传15秒板载串口日志即可分阶段定位。CAM0完整原图闭环待板测，原15fps/1080p60/滤镜逻辑未改。
