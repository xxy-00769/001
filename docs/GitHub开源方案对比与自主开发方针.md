# GitHub 开源方案对比与自主开发方针

> 日期：2026-10-19。项目：MES50HP / PGL50H + 香橙派 5 16GB / RK3588S 的 ADAS 作品。
> 用户决策：外部工程用于比较方法，不指定任何一个仓库为开发底座；系统最终画面统一由香橙派输出；后续增加无识别叠加的原视频预览入口。单 FPGA 与双 FPGA 均作为工程路线比较，第二块板不是默认采购项。
> 核查方式：GitHub 仓库检索、README、固定提交的目录和关键源码静态审查。没有运行下载工程的脚本，没有重新综合、烧录或复测作者性能。以下“存在实现”表示源码证据，不表示已在本项目实物验证。

## 1. 这次调研要解决的问题

1. 不同作品怎样划分 FPGA 与 ARM 的任务？
2. 四路究竟是四个独立视角，还是同一来源的多尺寸版本或重复显示？
3. 双 FPGA 是各自上传 ARM、相互串接，还是按不同计算任务分工？
4. 哪些设计思路适合 PGL50H，哪些受其他厂商 IP 和硬件限制？
5. 怎样形成自己的模块、数据协议、验收和迭代顺序，而不是拼接几个工程后难以调试？

本轮提交了 18 组检索关键词，包括 FPGA 双板、双板视频、双板以太网、FPGA RK3568、紫光视频、FPGA Aurora、环视鸟瞰等。关键词搜索每组最多检查前 8 项；部分请求遇到 API 限流，无结果不等于不存在相关开源。再通过已知项目、仓库引用与 Git 目录补充。详细比较 12 个有方法或关键源码证据的参考项目，另将证据不足的候选单列。

## 2. 参考项目总表

| 编号 | 仓库 | 实际方法 / 技术路线 | 借鉴重点 | 使用边界 |
|---|---|---|---|---|
| P01 | [flytt-away/FPGA-Video-Capture](https://github.com/flytt-away/FPGA-Video-Capture) | PGL50H，双目和 HDMI，四路 DDR 缓存，缩放，HDMI/网络/PCIe 输出，主机识别 | 多源缓存、缩放、输出解耦 | 仅作一个案例；默认 HDMI 占两个通道，网络替代连线被注释；当前缺完整上位机 |
| P02 | [xuanshao-yyy/rk3568_fpga_chinese_plate_locate](https://github.com/xuanshao-yyy/rk3568_fpga_chinese_plate_locate) | 单/双盘古 50H，通过独立网络链路向 RK3568 发送主图和模型输入流 | 双板 ARM 汇总、分包校验、最新帧、RGA/MPP/RKNN 分工 | 三路流来自同一视角；原设计有多个 ARM 网口，不能照搬到香橙派单千兆口 |
| P03 | [x-hao-v/dual-fpga-image-transmission](https://github.com/x-hao-v/dual-fpga-image-transmission) | 两块安路 FPGA，摄像头/SD 输入，经 UDP 互传，SDRAM 缓存和 HDMI 显示，Python 上位机 | 双板分方向调试、帧号/包号、完整帧显示 | 作者列出未重编译、历史时序违例和协议不一致；适合研究，不作为已通过验证的基线 |
| P04 | [xiaobai47-x/FPGACompeteCode](https://github.com/xiaobai47-x/FPGACompeteCode) | 双安路板采集/传输与处理分工，接收侧有 28×28 图像提取、二值化、BRAM、识别接口和返回通道 | 数据通路与结果通路分开、异构任务划分 | 接收顶层含神经网络待完成 TODO，不能按简介认定完整识别闭环已实现 |
| P05 | [MEEPproject/aurora-raw](https://github.com/MEEPproject/aurora-raw) | Alveo U280，Xilinx Aurora 64b/66b，四通道高速点对点，数据生成/校验 | 高速链路分层、link-up/reset、流握手、先测数据链再接业务 | 不是摄像头工程；Xilinx Aurora/GT 与 Pango HSST 不可直接互换 |
| P06 | [enjoy-digital/liteiclink](https://github.com/enjoy-digital/liteiclink) | SerWB：两块 FPGA 以三线串行连接，远端 Wishbone 外设映射；另有 SerDes 支持 | 板间控制、远端寄存器、链路初始化和 PRBS 测试 | 示例是控制/内存访问，不是四路视频；Pango PHY 需另行适配 |
| P07 | [shanyinshuiyue/License_Plate_Recognization](https://github.com/shanyinshuiyue/License_Plate_Recognization) | 紫光 FPGA 经 PCIe 上传 RK3568，应用与内核驱动、模型部署分层 | PCIe 用户态/内核态边界、设备节点、DMA 与应用衔接 | 工程平台为 RK3568_MES2L100H，非本项目直接可用；需审查内核、DMA 与接口 |
| P08 | [ColorStripes/FPGA_NPU_RK3568](https://github.com/ColorStripes/FPGA_NPU_RK3568) | PG100H + RK3568，YOLOv5n INT8、RTL 算子、指令和逐层参考验证 | 如何做算子预算、量化和逐层金标准 | 这是把模型放进 FPGA 的高成本路线；PGL50H 首版不照搬 |
| P09 | [ml13c/FPGA-Dashboard](https://github.com/ml13c/FPGA-Dashboard) | Artix-7，OV7670，Gray FIFO 跨域，DDR2 多客户端仲裁，图层合成和告警优先级 | CDC、缓存所有权、公平仲裁与实时性 | 单摄像头 VGA 工程，不是四路或双 FPGA；MIG 等 IP 需替换 |
| P10 | [neozhaoliang/surround-view-system-introduction](https://github.com/neozhaoliang/surround-view-system-introduction) | OpenCV 鱼眼标定、remap、投影、重叠加权、亮度/白平衡、线程化输入 | 真正环视的算法步骤和软件分层 | 需要匹配的四方向相机视角和标定数据；不是把任意四个视频拼起来 |
| P11 | [dyfcalid/CameraCalibration](https://github.com/dyfcalid/CameraCalibration) | 普通/鱼眼内参、外参/单应性、鸟瞰融合、时间对齐工具 | 标定流程、模型选择、离线参数验证 | 方法可比较；根许可证为 GPL-3.0，代码复用需按实际范围处理 |
| P12 | [alexforencich/verilog-ethernet](https://github.com/alexforencich/verilog-ethernet) | MAC、ARP、IPv4、UDP 分层，AXI-Stream/FIFO，RGMII 封装和测试 | 自己的传输层结构、仿真方法、背压边界 | 原仓库已声明被 [fpganinja/taxi](https://github.com/fpganinja/taxi) 取代；此轮审查旧库关键模块，未审查新库 |

P02、P03、P04、P05、P06 分别提供了双 FPGA 的不同方法；不能把它们都概括成“两个板子接起来就能四路”。

## 3. 双 FPGA 案例 A：两块采集板，各自上传 ARM

对应 P02。这是与“两个 FPGA 扩展输入、一个 ARM 汇总”最接近的案例。

```text
视频源 A → FPGA A → 以太网链路 A → RK3568 接收器 A ┐
                                                 ├→ 推理、跟踪、应用与显示/编码
视频源 B → FPGA B → 以太网链路 B → RK3568 接收器 B ┘
```

### 3.1 已看到的源码证据

- `source/fpga_dual/fpga_eth1/rtl/hdmi_ddr_ov5640_udp_top.v`：注释描述 HDMI 720p60 隔帧采集，形成 720p30 源，再生成三种传输流。
- FPGA 目录包括 `ovup_packet_header.v`、`ovup_udp_three_stream_arbiter.v` 等协议与调度模块。
- `source/rk_host_dual_udp/src/main.cpp`：默认绑定 `192.168.10.1` 和 `192.168.11.1`，两套 `CameraPipeline` / Receiver，线程名分别区分 eth0、eth1。
- `three_stream_receiver.cpp`：检查 magic、版本、尺寸、像素格式、总字节数、分块数、分块编号和偏移；按位图识别重复块，只有分块收齐后发布帧。
- 同一文件有不完整帧统计、超时处理、旧帧判断、设备帧号复位后的重新同步及 `recvmmsg` 批量收包。

### 3.2 “三路流”究竟是什么

| 流 | 规格（源码/说明默认值） | 用途 |
|---|---|---|
| S0 | 1280×720 RGB565，30fps | 主显示/保存 |
| S1 | 320×320 RGB888，20fps | 车牌模型输入 |
| S2 | 640×640 RGB888，10fps | 交通模型输入 |

这三个数据流是同一视角的不同处理版本，不是三个摄像头。两块板发送六条逻辑流，也不能据此认定有六个独立视角，更不能直接当作本项目的四路独立采集。

可借鉴的是：一幅图像可以服务多种任务，避免 ARM 重复做部分预处理；但是否值得在 FPGA 预先产生多尺寸流，要一起计算通信开销、处理精度和任务需求。

### 3.3 为什么不能直接照搬到香橙派 5

按这些默认规格，仅像素载荷每板约为：

```text
S0：1280×720×2×30 = 55.296 MB/s
S1： 320×320×3×20 =  6.144 MB/s
S2： 640×640×3×10 = 12.288 MB/s
每板合计             73.728 MB/s = 589.824 Mb/s
两板合计            147.456 MB/s = 1,179.648 Mb/s
```

还没有计网络包头。这解释了其两套独立接收网络链路的价值；香橙派 5 板载只有一个千兆口，经交换机汇总后仍受单口限制。

本项目若选择该拓扑，应自行设计分辨率/帧率/像素格式预算，而不是复制多流参数。巨型帧也要核对端到端支持；首版可采用标准 MTU 后优化，不能只在 ARM 设置 MTU 就认为 FPGA/交换机都兼容。

### 3.4 对自己的方案有什么启发

- 双板不一定要先相互传图。每板独立采集、由 ARM 统一处理，能减少一段转发、主板缓存和串接故障。
- 两块板可以共用一套参数化 RTL，并使用不同的板号、MAC/IP、会话与路号；这是设计建议，不代表参考仓库已验证每板双目四路。
- 学习其完整帧、最新帧和统计方法，自行定义满足本项目的协议和接口。
- 保留各独立视角，比只剩一幅低分辨率四宫格更有利于后续标定、检测和显示布局。

## 4. 双 FPGA 案例 B：母板、子板互传图像

对应 P03，板型为安路 EG4S20BG256。

```text
摄像头 → 母板：处理、SDRAM → UDP → 子板：SDRAM → 显示
                       ↑                    │
                       └── SD 图像/控制命令 ─┘
```

### 4.1 源码与说明的对应关系

- 母板 `muban/import/top.v` 中组织相机、处理、缓存和发送路径。
- 子板 `ziban/prj2/import/UDP_Example_Top.v`、`udp_packet_to_sdram.v` 中组织接收、包头跳过、写入缓存和显示。
- `Final_version_of_upper_computer.py` 中有 32 字节包头、636 字节图像块、帧缓冲及不完整帧超时处理。
- `udp_mode_ctrl.v` 处理输入/图像处理模式切换。

这说明双板串接的核心不是增加插槽，而是把板间链路做成另一种“像素输入”，接收侧还要重新建立缓存与输出节奏。

### 4.2 值得学习的地方

1. 先分方向验证：A→B 图像、B→A 图像、B→A 控制；不要第一次联调就同时开启全部业务。
2. 图像需要自定义包头和重组，不能认为 UDP 一包就是一帧。
3. 采集、处理、显示端时钟不同，通过 FIFO 和帧缓存隔离。
4. 处理模式和图像源应由明确状态机控制，并在帧边界切换。

### 4.3 不应复制的做法

作者明确说明当前源码修改晚于历史比特流，且历史时序有负裕量；这轮未复测。不同方向的网络载荷格式也不一致，子板接收不像 Python 上位机那样完整检查帧号/包号。

这些情况正好提示我们：两端协议必须统一，不能只靠包长度猜格式；“上位机能正确重组”不等于“第二块 FPGA 也有同样恢复能力”。还要处理全网络唯一地址，原项目某些运行场景中的子板/电脑默认 IP 相同，不能原样同时接入。

对 MES50HP，如果确实需要主 FPGA 汇总，可将 A 板的两路像素经以太网送 B 板，B 再合并本地两路；但 B 要承担全部汇总缓存、调度和 ARM 出口。当前由香橙派输出显示，没有必要仅为显示而先增加这个汇聚层。

## 5. 双 FPGA 案例 C：一块采集处理，另一块计算并回传结果

对应 P04，项目说明宣称 A 板采集/颜色处理，B 板做数字识别、结果回传。

### 5.1 代码实际支持怎样的判断

接收顶层 `anlu _text_2_2_rx/.../UDP_Example_Top.v` 包含：

```text
UDP 接收 → 图像提取/采样 → 二值化 → 28×28 BRAM
                                     ↓
                             neural_net_if 接口
                                     ↓
                              UDP 结果发送
```

但该顶层约 374–385 行注释明确写着：神经网络完成后再启用相关状态，目前帧准备好后直接回到 IDLE，并留有 TODO。`neural_net_if.v` 是送入像素、等待 `nn_done`、取 `nn_result` 的接口状态机，本身不是完整神经网络计算核心。

因此，能够学习分工和数据握手，不能以仓库简介认定完整识别闭环已经发布。发送侧某些文件还存在空文件/历史变体，选模块前要核对实际工程引用。

### 5.2 对本项目的启发

- “视频通道”与“结果通道”分开设计。图像数据大，决策/控制结果小，队列和优先级不必相同。
- 第二块 FPGA 不一定只是扩展摄像头，也可以承担特定算法；但增加算法板应有明确的计算瓶颈证据。
- 香橙派已具备 NPU，首版没有必要再制造第二套 FPGA 神经网络任务。双 FPGA 更适合优先解决输入数量和采集分担。

## 6. 双 FPGA 案例 D：高速串行 / 光口点对点

对应 P05。源码目标是 Alveo U280，`ip/aurora6466b.tcl` 调用 Xilinx `aurora_64b66b`，配置四条通道和 Streaming 接口；顶层有发送握手、接收有效、lane-up、channel-up、复位，以及测试数据生成/校验模块。

```text
FPGA A：业务数据 → 异步 FIFO → 串行链路适配 → 高速收发器
                                                    ║
FPGA B：业务输入 ← 异步 FIFO ← 串行链路适配 ← 高速收发器
```

可借鉴的是开发顺序：

1. 首先确认参考时钟、收发器锁定、链路就绪和复位时序。
2. 使用计数器/测试码验证持续传输与错误恢复。
3. 再增加业务帧边界、路号、长度和错误检查。
4. 最后接入真实摄像头像素和 DDR。

Aurora 不等于视频协议。即使串行链路通了，仍需自己的视频分包、帧号、背压处理和缓存。相机不能因链路暂停而无限等待，要规定溢出后的整帧丢弃策略。

MES50HP 有两个 SFP，板载 Pango HSST 能力和时钟需按手册验证。其物理资源、模块速率和 PDS IP 与四通道 U280 工程不同，不能直接导入 Xilinx IP。若以后采用光纤，可参考分层和验证方法，再用 Pango 支持的 IP 或自定义协议实现，先不把这条链路放进最小可用作品的关键路径。

## 7. 双 FPGA 案例 E：远端寄存器和控制总线

对应 P06。`bench/serwb/demo/README.md` 明确给出 ECPIX-5 主 SoC 与 iCEBreaker 外设 SoC 的双板演示，三线连接，通过 SerWB 将远端寄存器/SRAM 映射到主 SoC 的 Wishbone 地址空间。

这不是成熟四路视频方案。它值得借鉴的是：

- 所有板卡有清晰的寄存器地图与设备身份。
- 链路状态、PRBS 错误计数、远端读写能独立于视频验证。
- 控制平面不必依赖大视频帧才能工作，故障时仍应可读状态和重置模块。

源码含厂商相关 PHY，Pango 适配需要新增工作。不能把 README 的最高线速当成三线低速示例在任意板卡上的视频吞吐。

## 8. 其他方法如何整合

### 8.1 PCIe 图传：参考 P07

已核对内核驱动 `pango_pci_driver.c` 和应用 `main.cpp`，可以看到 PCI 设备/BAR、ioctl 和应用层采集接口的分层。这比只看“PCIe 更快”更有价值。

自己的设计仍需独立处理缓冲所有权、DMA 地址/一致性、超时、设备重启和驱动安全；不能复制 RK3568 的内核模块到 RK3588S 后直接加载。香橙派 5 的 M.2 PCIe 2.0 x1、转接、复位和参考时钟仍须实物验证。

### 8.2 FPGA 神经网络：参考 P08

项目源码中存在卷积等算子组织、NPU 顶层、PCIe 到 NPU 的指令/数据桥接，说明“FPGA 跑 YOLO”实际需要量化、存储布局、算子调度、DMA 和逐层比对。

可以学习逐层参考值与误差验证的方法。自己的第一版仍采用 PGL50H 做图像采集/明确的像素算子、香橙派 NPU 做检测。是否后续把个别算子移入 FPGA，由性能分析决定。

### 8.3 缓存与 CDC：参考 P09

已阅读 `async_fifo_gray.v` 和架构/设计决策文档。其单摄像头系统也需要 Gray 指针跨域、多消费者存储仲裁、缓存和告警优先级，说明四路系统首先是时序和数据所有权问题。

自己的首版可优先使用经验证的厂商异步 FIFO/IP，再学习 Gray FIFO 原理；不能为了“原创”在没有验证时替换关键 CDC 模块。不同板卡的 DDR2/MIG 和本板 DDR3 控制器实现分别处理。

### 8.4 环视与标定：参考 P10、P11

P10 的 `fisheye_camera.py` 有畸变映射、`cv2.remap` 和 `warpPerspective`；`birdview.py` 有重叠区域权重拼接、亮度平衡等方法。P11 覆盖普通与鱼眼相机标定，以及鸟瞰生成和按时间命名图片的对齐工具。

自己的流程应是：

```text
相机型号/安装条件 → 内参/畸变标定 → 地面对应点/外参
→ 投影映射 → 相邻区域权重 → 曝光/亮度处理 → 动态验证
```

普通 OV5640 镜头不能直接套鱼眼模型。标定参数与图像尺寸、裁剪和缩放绑定。四段互不相关的道路视频可证明多路输入与识别，但不能凭它们验证真实车辆环视融合。

检测建议优先针对各独立相机视图或 ROI，环视地面投影作为另一条显示/空间理解路径，避免把严重投影变形后的行人直接当作原始检测输入。

### 8.5 网络基础：参考 P12

已核对 `udp_complete.v`、`eth_mac_1g_rgmii_fifo.v`、`rgmii_phy_if.v`。其分层体现了应用帧、UDP/IP/ARP、MAC、PHY 适配的边界，配套测试比手工逐包观察更容易发现问题。

RGMII 时钟、DDR I/O 原语仍是器件相关内容，不能把 Xilinx 原语直接放进 Pango 工程。原仓库已宣布后继项目 taxi；不能把旧项目写成仍持续维护的新选择，也不能在未审查 taxi 前保证迁移成本。

## 9. 三种系统拓扑的取舍

| 拓扑 | 适用需求 | 工作量与风险 | 本项目建议 |
|---|---|---|---|
| 单 FPGA 混合四路 → ARM | 先完成比赛式多场景演示，不坚持四颗实体摄像头 | 双目并行、HDMI、网络输入、四路缓存仍需开发；无需第二板 | 当前优先验证候选，不指定开源底座 |
| 双 FPGA 各两路 → ARM 汇总 | 需要扩展为四颗实体摄像头 | 独立板号/路号、单千兆汇总预算、跨板时间对齐 | 双板优先候选；不必先做 FPGA 间图像转发 |
| FPGA A → 主 FPGA B → ARM | 确实需要 B 集中处理/融合或 ARM 只有一个特定入口 | 新增一次传输、缓存、主板仲裁与单点故障 | 没有明确收益前不优先 |
| 双 FPGA 分计算任务 | 某一硬件算法在单板资源/时间上超限 | 任务依赖、特征/像素传输、额外验证 | 等实测瓶颈，再评估 |
| 双 FPGA 高速串行互联 | 双板必须交换大量原始像素且以太网不足 | 收发器/IP/参考时钟/协议适配工作最多 | 后期技术研究候选 |

双板优先采用采集节点并行上传的原因是最终画面和 AI 都在香橙派；提前在主 FPGA 汇聚不会自动提高 ARM 入口带宽，也不会自动完成相机时间同步。

## 10. 我们自己的模块和接口方针

### 10.1 总体数据流

```text
独立视频源
  ↓
FPGA：输入适配 → 格式规范化 → 像素预处理 → FIFO/DDR → 通道调度
  ↓ 传输适配器：首版 UDP；有条件时替换为 DMA/UVC
香橙派：完整帧接收 → 不可变帧缓冲 → 按路对齐/分发
                              ├→ 各视角/ROI → RKNN → 检测与规则
                              ├→ 标定映射/鸟瞰融合
                              └→ 无识别叠加预览
                                         ↓
                        香橙派统一显示、事件记录、可选视频保存
```

建立自己的模块接口，不要求复刻任何工程的目录。复用来源清楚的单个模块时保留出处、许可证和验证记录；项目系统集成、协议、验收和应用逻辑由我们定义。

### 10.2 四个身份不能混淆

- `board_id`：哪块物理采集板。
- `channel_id`：哪个独立输入/视角。
- `stream_kind`：该视角的主图、模型输入、ROI 或其他派生版本。
- `session_id + frame_id`：哪次运行的哪一帧。

相同画面的两种尺寸应使用同一通道身份、不同 stream_kind，不能把尺寸分支计成独立相机。重启后建立新会话，避免旧结果套到新帧。具体二进制头设计与原手册第 12 章统一，增加字段时要提升版本并重新计算 MTU，不能照搬多个参考项目的不同包头。

### 10.3 传输选择

当前推荐首版千兆以太网，是基于成本、可用接口和目标数据量的技术判断，不是用户限制。对四路 `640×360 / RGB565 / 30fps`，总纯像素约为 `442.368 Mb/s`；15fps 起步约为 `221.184 Mb/s`。这给单千兆链路留出协议与调度余量，但仍需要真实收包/DDR/CPU 压测。

若要四路 720p30 原始 RGB565，总载荷约 `1.769 Gb/s`，单千兆不足。届时比较：降低部分视角帧率、增加 ROI、压缩、经验证的 USB3 视频采集，或者 PCIe。不要先买转接硬件、后补需求。

UDP、DMA、UVC 接收后应统一输出帧描述对象，后端推理与显示不绑定某一种接口。低延迟策略是优先最新完整帧，不让旧帧无限排队；完整性检查不能为了追求 FPS 而去掉。

### 10.4 原视频预览与识别输出

按用户决定，所有正常运行画面均由香橙派输出。MES50HP HDMI-OUT 只保留板级调试或备用，不进入首版最终显示的必需链路；不再开发“识别框回传 FPGA 绘制”的主线功能。

建议后续两个入口（当前只是接口规划，尚未编写脚本）：

- `preview_raw.py`：无检测框/驾驶状态叠加的接收画面、分路预览或四宫格。
- `run_adas.py`：模型推理、规则、告警、叠加与最终显示。

二者共用一个采集/重组服务和同一帧缓冲。在一个 UDP 端口启动两个独立接收脚本不会自然各得到一份完整流；不要用端口复用碰运气。同理，一个窗口的绘制也不能原地修改供另一消费者使用的像素缓冲。先将显示模式做成同一程序中的开关，再按需要拆分入口和 IPC。

“原视频”在这里默认指香橙派收到的无 AI 叠加画面。若 FPGA 已缩放、灰度化或改色，关闭 OSD 无法恢复传感器原图；需要原始彩色视频时，在 FPGA 保留可选择的旁路/彩色通道，并单独预算带宽。可以分别标注 source、FPGA processed、AI annotated，避免演示含糊。

LED、按键、配置、心跳和告警仍可在 FPGA 与香橙派之间交换小消息；取消检测框回传不等于取消控制链路。

### 10.5 文件输入与最终输出的接口冲突

香橙派最终 HDMI 连接显示器后，不再把同一个 HDMI 口默认用于给 FPGA 播放输入。实验室可用电脑 HDMI 提供模拟源；独立作品的 U 盘模式优先研究香橙派解码后经双向数据链路送 FPGA，FPGA 处理返回，香橙派识别和显示。

这增加发送和接收逻辑，但与统一输出决定一致。若采用额外独立显示输出给 FPGA，需先核对板卡/BSP 的多显示能力与显示管线，不能将 HDMI 分配器当作两个独立内容的输出。输入发送队列和返回接收队列必须分开，防止重复处理最终画面。

## 11. 实施步骤与阶段验收

| 阶段 | 开发内容 | 进入下一阶段前必须拿出的证据 |
|---|---|---|
| 0 方案规格 | 单板/双板拓扑、输入来源、目标格式、像素算子、传输接口、最终显示端 | 一页系统图、流量表、输入/派生流身份表；不预先指定第三方工程为底座 |
| 1 板级基线 | 保护厂商原例程，LED、DDR、一路输入；香橙派镜像、NPU、显示 | 从源码重建记录、板卡版本、引脚/时序、NPU 单图结果 |
| 2 通信测试 | 计数器、纯色、棋盘格、分包与重组、双向控制 | 字节比对、乱序/重复/缺包/重启后恢复；图传与控制分别统计 |
| 3 单路应用 | FPGA 真实输入与预处理，香橙派显示、RKNN、规则 | 识别帧确实来自 FPGA；原预览和带框画面都能显示；无积压增长 |
| 4 单板多路 | 双目独立，再加 HDMI/网络输入 | 每路不同动态内容，逐路帧号/FPS/错误计数；任一路断流其他路继续 |
| 5 双板分支 | 若需要第二板，各自双路、独立身份与汇总 | 先证明每板两路，再证明系统四路；ARM 总入口带宽、时间差和单板重启恢复 |
| 6 标定融合 | 合适视场与数据、相机模型、投影与加权融合 | 标定误差、拼接缝/重影、运动目标测试；不能只给四宫格 |
| 7 性能与交付 | 最新帧策略、ROI/算子优化、长稳与离线运行 | 端到端延迟分布、逐路采集/推理/显示 FPS、丢帧、资源/时序、版本对应 |

两板帧号相等不等于同步；网络时间戳也不等于同步曝光。跨板使用共同可见事件或经过测量的时基映射验证对齐。普通按接收时间选最近帧只能作为初期近似，动态全景需要单独评估。

## 12. 如何判断一个开源仓库值得用

按下列顺序保留证据，避免只比较 README 的功能词数量：

1. 实际板型、器件、时钟、外设与输入数量。
2. 工程引用的源码与模块是否存在，而非空文件、接口壳、被注释的实例或只有编译产物。
3. 当前提交与比特流、时序报告是否对应；无法对应就不引用为当前可运行证明。
4. 协议是否包含完整帧、丢包和复位恢复，是否只在电脑端实现而 FPGA 接收端没有。
5. 帧率指采集、输出刷新、传输还是推理，是否存在重复帧。
6. IP/驱动是否绑定厂商和内核，移植代价是否超过自建一个清晰模块。
7. 许可证、第三方模块来源、模型/数据来源是否明确。

已核实：P01、P10 为 MIT；P06 为 BSD-2-Clause；P11 为 GPL-3.0；P12 的 COPYING 为 MIT；P05 包含 Solderpad/Apache 相关授权说明。P02 中多个子目录有自己的第三方许可声明，不能概括为整个仓库统一许可；其他项目本次未全面完成许可审查。方法比较与直接复制代码应分开记录。

## 13. 证据不足或暂不优先的候选

- `frogtao/Ethernet-transmission-system`：README 声称双板点对点和双目拼接，但本次读取的根目录仅列 README，未找到可审查 RTL。保留作线索，不作为实现参考。
- `yunhuaCN/fpga-race`：板型接近 MES50HP_v2，但说明较少；可作后续板型对照，不因板名相同就认定双目并行已完成。
- `Cyrille175/multi-camera-fpga-vision-system`：检索描述匹配多摄像头，但仓库体量很小，本轮没有获得足够实现证据，不进入主比较。
- `fpgadeveloper/Aurora-to-Ethernet-Bridge`：存在历史 ML505/EDK 等工程目录，适合后续研究桥接结构；此轮只核对目录，未深入旧工具工程。
- 搜索到部分同一作者的多个近似环视仓库，未把它们当成多个独立方法计数。

## 14. 当前方针

自己定义一个输入和传输可替换的采集框架：FPGA 做独立采集、缓存、明确的硬件图像算子和可测量的数据调度；香橙派做帧完整性/时间处理、NPU、标定融合、驾驶逻辑和全部正常显示。单板先验证混合四路；确需四颗实体摄像头时，双板优先采用各采两路、ARM 汇总的拓扑。板间串接与高速光链路保留到需求和性能证明有必要时。

外部项目提供方法和可验证模块，不决定我们的整个工程。是否直接复用某模块，应经过来源记录、接口审查、模块验证和资源/时序检查后再决定。


## 15. 固定提交与关键证据索引

下列链接固定到本次读取的提交，便于后续复查。只读过目录或 README 的其他候选没有混入这份源码/方法表。

| 编号 | 固定提交 | 关键文件 |
|---|---|---|
| P01 | `2845007c4b65` | [ddr_test_top.v](https://github.com/flytt-away/FPGA-Video-Capture/blob/2845007c4b65c781feafa0c9f80eaef6ae35e3f1/board_3_oneboard_design/source/ddr_test_top.v) |
| P02 | `237c6e95f70e` | [three_stream_receiver.cpp](https://github.com/xuanshao-yyy/rk3568_fpga_chinese_plate_locate/blob/237c6e95f70ef494a64384b5b226d52c9e46d151/source/rk_host_dual_udp/src/three_stream_receiver.cpp) |
| P03 | `1a78125b1adc` | [udp_packet_to_sdram.v](https://github.com/x-hao-v/dual-fpga-image-transmission/blob/1a78125b1adcdc43406aa4b0a98eabdbb9475877/ziban/prj2/import/udp_packet_to_sdram.v) |
| P04 | `30cf0c35de78` | [UDP_Example_Top.v](https://github.com/xiaobai47-x/FPGACompeteCode/blob/30cf0c35de78bbf96cc0c825032e115d6b5d54e8/anlu%20_text_2_2_rx/UDP_EG4_6.2/source_code/rtl/UDP_Example_Top.v) |
| P05 | `53a198bc0bba` | [aurora_raw_top.vhd](https://github.com/MEEPproject/aurora-raw/blob/53a198bc0bba001bd722a94ad95f9c2c3ffb47a8/src/aurora_raw_top.vhd) |
| P06 | `6e69216944e9` | [README.md](https://github.com/enjoy-digital/liteiclink/blob/6e69216944e94c69f5a7d58d5c6d75dc3d754242/bench/serwb/demo/README.md) |
| P07 | `60093e2eb87c` | [pango_pci_driver.c](https://github.com/shanyinshuiyue/License_Plate_Recognization/blob/60093e2eb87c63d8f555464ed87b5a0d3762b35d/%E4%B8%8A%E4%BD%8D%E6%9C%BA%E6%8E%A7%E5%88%B6%E4%BB%A3%E7%A0%81/driver/pango_pci_driver.c) |
| P08 | `e841055086c4` | [npu_top.v](https://github.com/ColorStripes/FPGA_NPU_RK3568/blob/e841055086c4e550cdca2b5584f9fcc4a19757dd/FPGA/PG_100H/yolo_fpga_hdmi/source/npu/npu_top/npu_top.v) |
| P09 | `3a14499e225d` | [async_fifo_gray.v](https://github.com/ml13c/FPGA-Dashboard/blob/3a14499e225d09c6380941e13c6a1da84828ecb3/final_version/async_fifo_gray.v) |
| P10 | `0c40d7e12443` | [birdview.py](https://github.com/neozhaoliang/surround-view-system-introduction/blob/0c40d7e12443a7f16b2adae6f79fae2f6d6ee071/surround_view/birdview.py) |
| P11 | `67ad1b985aa8` | [surroundBEV.py](https://github.com/dyfcalid/CameraCalibration/blob/67ad1b985aa89cc14dca90886412cba4938df2c7/SurroundBirdEyeView/surroundBEV.py) |
| P12 | `77320a9471d1` | [udp_complete.v](https://github.com/alexforencich/verilog-ethernet/blob/77320a9471d19c7dd383914bc049e02d9f4f1ffb/rtl/udp_complete.v) |
