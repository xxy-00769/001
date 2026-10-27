# HDMI_DDR3_OV5640 — 盘古 50K 视频通路工程

> 从官方例程 `HDMI_DDR3_OV5640_test` 整理而来的**干净、可移植**工程副本。
> 用于「全国大学生嵌入式芯片与系统设计竞赛 · FPGA 创新设计赛道 · 紫光同创选题三」的基础任务 1。

## 当前道路测试版本（2026-10-16）

- 主用基线已按上板反馈恢复为第 4 版：`bitstreams/4_road_markings_filtered_cmos1.sbit`。该文件保持原样，未重新生成或覆盖。
- 当前源码为第 7 版斑马线候选实验：`bitstreams/7_zebra_candidate_v4_cmos1.sbit`。基于第 6 版帧修复，保留第 4 版标线算法；尚未烧录和现场验证。上板顺序及图示说明见 `bitstreams/7_zebra_acceptance.md`。
- 第 6 版帧完整性测试 `bitstreams/6_road_framefix_v4_cmos1.sbit` 保持不变。该版只修复行缓存和输出帧同步，不含斑马线功能；第 4 版继续作为上板对照基线。
- 当前顶层为 CMOS1、`MODE=4`、`DIAG_CYCLE=0`，固定显示原图及道路标线候选，不再轮播。
- 绿色表示白色标线候选，青色表示黄色标线候选；已取消模式 4 的全画面红边。
- 恢复第 4 版识别范围：720 行画面从零基第 405 行开始，使用原来的道路梯形。此次不保留第 5 版“下三分之二”的范围扩展。
- 恢复 8 像素局部对比度、连续 6 行支持，以及第 4 版的颜色判断；标线模块的像素/控制延迟为 119 拍。
- 仅黄色候选进行横向宽度过滤：测量时连接不超过 4 像素的小缺口，宽度门限随深度从 64 增至最多 96 像素，整段过宽黄色候选不叠检测颜色。白色候选不经过此宽度过滤。
- 第 5 版 `5_road_roi23_precision_cmos1.sbit` 因上板反馈“绿色识别面积过大、画面模糊”停止作为主用；原因尚未定位，不能用仿真通过代替画质验证。
- 第 5 版改动源码、测试模型、输出、说明和报告已备份至 `experiments/v5_roi23_rejected_20261016/`。本次帧修复前的第 4 版源码和说明另存于 `experiments/v4_before_frame_fix_20261016/`，两者均不参与编译。
- 已复现旧行缓存会在长帧间空白期间重复输出旧像素，并丢失或错用边界行。新缓存只存有效像素，补齐四边邻域，按输出首像素重建帧同步。此修复尚需上板确认对误检与清晰度的实际影响。
- 第 6 版最终源码四项流水线回归全部通过，共核对 6,501,120 个像素，涵盖完整 RGB、滤波亮度、ROI 坐标、叠色及紧邻帧同步；详细记录见 `tests/README.md`。
- 第 6 版最终编译日志：`build_frame_integrity_v6_final.txt`；对应报告已归档。当前 `generate_bitstream/`、`report_timing/` 为第 7 版构建输出，不代表第 4/6 版。没有自动烧录。
- 第 6 版完整编译通过，时序报告为 `All Constraints Met`；摄像头输入延时约束仍未补齐。对应源码、测试及报告保存于 `experiments/v6_framefix_20261016/`。
- 恢复后的四组 RTL 回归全部通过，共核对 7,372,800 个像素，候选数量与第 4 版原记录一致。详细记录见 `tests/README.md`。
- 第 4 版原构建日志为 `build_road_markings_filtered_holdfix.txt`；现有约束满足，但摄像头输入延时约束仍未补齐。
- 浏览器中的道路图片需要尽量全屏、居中；本版不自动定位网页内图片。零碎误检仍可能存在，强曝光、偏色、宽标记和偏离中心的弯道也可能漏检。
- 这是标线候选提取，不等于虚实线分类、车道归属或变道决策，仍需上板验证。
- 回归样例、模型与 RTL 仿真说明见 `tests/README.md`。下文资源表和旧模式说明为历史记录。

### 第 7 版新增项

- 单独读取未叠色 RGB，分析下三分之二、中央 80% 的重复白条。要求白条宽度、暗色间隔、至少四条、连续 12 行以及连续两帧位置重叠；并不改变旧标线 ROI。
- 左上角条纹图标：灰色无候选、橙黄色单帧候选、品红色连续两帧候选；品红色细框只描边，结果晚一帧显示。
- `img_proc.ZEBRA_ENABLE` 默认关闭，当前顶层显式开启。关闭新模块的原有回归通过；摄像头、DDR、HDMI 和 `lane_detect.v` 未改。
- 30 组检测用例、3 张已有道路反例、76,800 像素叠加检查通过；两项整流水线回归共核对 6,451,200 像素。
- 构建日志 `build_zebra_candidate_v7.txt`；最终时序报告 `All Constraints Met`，输入接口仍存在未约束项，不是完整接口时序签核。
- 测试图位于 `tests/output/zebra/`。`rtl_confirmed.png` 是 RTL 仿真输出，不是实拍。算法边界和复现步骤见 `tests/ZEBRA.md`。
- 第 7 版源码、日志、报告快照位于 `experiments/v7_zebra_candidate_20261016/`，不参与当前编译。
- 这是合成样例验证过的候选启发式，尚无真实斑马线准确率数据，也不含行人识别、测距或驾驶决策。

---

## ⚠️ 先看这一条：许可证 2026-11-03 到期

```
D:\PDS\PDS_2022.2-SP6.1\Licnse\new_pds_F4A80DA47D72.lic
  -expire_date {2026-11-03}
  -host_id {F4A80DA47D72}      ← 绑定本机，换电脑无效
```

**比赛作品提交截止是 2026-11-04 18:00，许可证在前一天到期。**
10-12 那次编译时 PDS 已经弹过警告：*"The license will invalid in 22 days"*。

**必须在 11 月初之前重新申请 license**，否则最后关头改一版代码都编译不了。
申请入口在紫光同创官网 / 小眼睛科技的技术支持群。

---

## 1. 工程概况

| 项目 | 内容 |
| --- | --- |
| 器件 | **PGL50H-6FBG484**（Logos 系列） |
| 工具链 | **PDS 2022.2-SP6.1**（`D:\PDS\PDS_2022.2-SP6.1`） |
| 顶层模块 | `hdmi_ddr_ov5640_top` |
| 功能 | OV5640 摄像头 → DDR3 帧缓存 → HDMI 显示 |

### 数据通路

```
OV5640 (DVP 8bit, PCLK 84MHz)
   │        cmos1 / cmos2 两套接口，板上各有一个连接器
   ▼
cmos_8_16bit.v            8bit → 16bit RGB565
   ▼
wr_fram_buf / rd_fram_buf SDPRAM 乒乓缓冲（IP 核）
   ▼
DDR3_50H                  DDR3 控制器 + PHY（硬核，32bit / 15行 / 10列 / 3Bank）
   ▼
rd_buf → sync_vg          读缓冲 + 视频时序发生器
   ▼
ms72xx_ctl                 MS72xx HDMI 发送芯片 I2C 配置
   ▼
HDMI 输出                 r/g/b 各 8bit + pix_clk + vs/hs/de
```

### 摄像头二选一

`source/rtl/hdmi_ddr_ov5640_top.v` 第 22–24 行：

```verilog
//cmos1、cmos2二选一，作为视频源输入
`define CMOS_1      // cmos1作为视频输入；
//`define CMOS_2    // cmos2作为视频输入；
```

**两路引脚都在 `.fdc` 里做了约束，但同一时刻只有一路送显示。**

本次编译的时序报告**实测证实**了这一点：

```
W: Flow-4065: The port cmos2_pclk has a sdc constraint, but it do not connect to any pin.
C: STA-3009: The clock cmos2_pclk is not connected to any clock endpoints...
```

即 `CMOS_1` 生效时，**cmos2 的整条通路被综合工具完全优化掉了** —— 连时钟端点都没有。
要扩展成多路系统，第一步就是把这两路并行化（而不是简单地两个 `define` 都打开）。

### 资源占用（**本工程实测**，2026-10-16 完整编译通过）

| 资源 | 占用 | 总量 | 占比 |
| --- | --- | --- | --- |
| LUT | 5,355 | 42,800 | **12.51%** |
| Register | 5,228 | 64,200 | 8.14% |
| DRM18K（块 RAM） | 19.5 | 134 | 14.55% |
| APM（DSP） | 0 | 84 | 0% |
| IO | 136 | 296 | **45.95%** |
| HSST | 0 | **1** | — |

> 整条「采集 → DDR3 → HDMI」通路只吃 **12.5% 的逻辑资源**，DDR3 PHY 和控制器大量使用硬核，软逻辑开销很小。
> 这是 4 路系统可行的实测依据（按此外推 4 路系统约 33K LUT / 77%）。
>
> 注意 `HSST = 1`：PGL50H **只有 1 路高速收发器**，所以 PCIe 物理上只能做 ×1。
>
> `IO` 已用 46% 是个需要注意的数：再加 3 路摄像头（每路约 14 根）会到 ~56%，可行但要规划好 Bank。

---

## 2. 目录结构

```
HDMI_DDR3_OV5640\
├─ HDMI_DDR3_OV5640.pds        PDS 工程文件（全相对路径）
├─ hdmi_ddr_ov5640_top.fdc     引脚/时序约束
├─ flow.tcl                    ★ 编译流程模板（改这个）
├─ build.bat                   ★ 一键编译（自动复制 flow.tcl → impl.tcl）
├─ README.md                   本文件
└─ source\rtl\
   ├─ hdmi_ddr_ov5640_top.v     顶层
   ├─ img_proc.v                ★ 图像预处理流水线（灰度/中值/Sobel）
   ├─ cmos_8_16bit.v            DVP 8bit → RGB565
   ├─ fram_buf.v                帧缓存顶层
   ├─ sync_vg.v                 HDMI 时序发生
   ├─ ms72xx_ctl.v 等           HDMI 发送芯片 I2C 配置
   ├─ pll\                      PLL IP
   ├─ wr_fram_buf\              写帧缓冲 IP
   ├─ rd_fram_buf\              读帧缓冲 IP
   └─ DDR3_50H\                 DDR3 控制器 IP
```

> ⚠️ **`impl.tcl` 不要手动编辑**。`pds_shell -file` 会把它的绝对路径流程**追加**到脚本末尾，
> 跑一次追加一次。所以 `build.bat` 每次都从 `flow.tcl` 重新复制一份。
> **要改编译流程，改 `flow.tcl`。**

编译产物会生成在这些目录（首次编译时自动创建）：
`compile\` `synthesize\` `device_map\` `place_route\` `report_timing\` `generate_bitstream\` `log\`

---

## 3. 怎么用

**当前上板请选 `bitstreams/4_road_markings_filtered_cmos1.sbit`，摄像头接 CMOS1。**
排查帧完整性时使用单独命名的第 6 版测试文件；第 4 版始终保留供对照。
以下是后续修改源码时的重新编译方法；当前源码含帧修复，重新编译不会重现原第 4 版二进制。

### 方式 A：一键编译（推荐）

双击 **`build.bat`**。结束后比特流在：

```
generate_bitstream\hdmi_ddr_ov5640_top.sbit
```

### 方式 B：命令行

```powershell
cd "E:\FPGA drive\HDMI_DDR3_OV5640"
D:\PDS\PDS_2022.2-SP6.1\bin\pds_shell.exe -file impl.tcl -continue
```

### 方式 C：GUI（改代码、看时序报告时用）

1. 打开 PDS → `File` → `Open Project` → 选 `HDMI_DDR3_OV5640.pds`
2. 左侧流程面板里依次跑 `Synthesize` → `Device Map` → `Place & Route` → `Report Timing` → `Generate Bitstream`

> GUI 方式适合调试；批处理方式适合"改完就编一版"的快速迭代。

---

## 3.5 图像预处理流水线 `img_proc.v`

**新增模块**，插在 `cmos_8_16bit` 和 `fram_buf` 之间：

```
摄像头 RGB565 ──► img_proc ──► fram_buf ──► DDR3 ──► HDMI
                   │
                   ├─ RGB565 → 灰度 Y
                   ├─ 3×3 行缓冲（乒乓地址空间）
                   ├─ 3×3 中值滤波
                   └─ Sobel 边缘检测
```

### 输出模式

顶层 `hdmi_ddr_ov5640_top.v` 里的这一行控制显示什么：

```verilog
    img_proc #(
        .MAXW ( 2048 ),
        .MODE ( 4    )      // ← 改这里
    ) u_img_proc (
```

| MODE | 显示效果 |
| --- | --- |
| 0 | 原始彩色画面（验证旁路是否正常） |
| 1 | 灰度图 |
| 2 | 灰度 + 3×3 中值去噪 |
| 3 | Sobel 边缘（黑底白边） |
| **4** | **原始彩色 + 红色边缘叠加**（默认，演示效果最好） |

改完 MODE 重新跑 `build.bat` 即可。

### 实测资源代价（2026-10-16）

| 资源 | 加之前 | 加之后 | 增量 |
| --- | --- | --- | --- |
| LUT | 5,355 | **5,781** | **+426** |
| Register | 5,228 | 5,381 | +153 |
| DRM18K | 19.5 | **27.5** | **+8** |
| IO | 136 | 136 | **+0** |

> 整套三算法只花 426 LUT / 8 块 RAM。按此外推，**4 路各跑一套也才 ~1.7K LUT**，
> 资源完全不是瓶颈 —— 真正的瓶颈是 IO 和 DDR3 带宽。

### 设计要点（答辩可以用）

**行缓冲用「乒乓地址空间」，读写地址永不相撞。**

常规写法是读地址=写地址，此时行缓冲的行为取决于综合器把块 RAM 推断成
read-first 还是 write-first —— 换个工具版本就可能出一像素的错位。
本设计让 `par` 每行翻转一次，把 RAM 分成两半：当前行写 `{par, addr}`，
同时读 `{~par, addr}`。**两个地址必然不同**，所以结果与读写顺序无关，完全确定。

代价是多用一倍块 RAM（8 个 DRM18K），换来的是行为可预测。



1. 用 USB 线连接板子的 JTAG 口，确认 PDS 能识别到器件
2. PDS 菜单 `Tools` → `Configuration`（或直接跑 `D:\PDS\PDS_2022.2-SP6.1\bin\cdt_cfg.exe`）
3. 加载 `generate_bitstream\hdmi_ddr_ov5640_top.sbit`，执行下载
4. 接上 OV5640 摄像头和 HDMI 显示器

**预期现象**：`heart_beat_led` 心跳闪烁 → `ddr_init_done` 亮起 → `hdmi_int_led` 亮起 → 显示器出画面。

### 想先验证硬件？用现成的比特流

如果只是想确认板子/摄像头/显示器是好的，**不必先编译**，可以直接烧这些原厂已编译好的文件：

```
D:\BaiduNetdiskDownload\HDMI_DDR3_OV5640_test\generate_bitstream\CMOS1.sbit   ← 摄像头 1
D:\BaiduNetdiskDownload\HDMI_DDR3_OV5640_test\generate_bitstream\CMOS2.sbit   ← 摄像头 2
```

两个都烧一遍，就能确认**两路摄像头接口都是好的** —— 这是 4 路方案的第一道门槛。

---

## 5. 下一步：改造成 ADAS 工程

按竞赛方案的排期，在这个工程上依次做：

| 步骤 | 改动位置 | 目标 |
| --- | --- | --- |
| 1 | `hdmi_ddr_ov5640_top.v` | 去掉 `CMOS_1/CMOS_2` 二选一，让 cmos1 + cmos2 **同时**进 DDR3 不同区域 |
| 2 | 新建 `source/rtl/video_mux.v` | 2 宫格 / 4 宫格画面拼接 |
| 3 | 新建 `source/rtl/alg_*.v` | 灰度 → 3×3 中值 → Sobel → 车道线 / 斑马线 / 帧差 |
| 4 | 新建 `source/rtl/eth_udp.v` | 以太网 UDP，把 ROI 小图和检测结果送给 ARM |
| 5 | 新建 `source/rtl/osd_overlay.v` | 检测框 + 告警文字叠加到 HDMI 输出 |

**先做第 1 步。** 它是所有后续工作的基础，也是风险最高的一步。

---

## 6. 常见问题

**Q: 打开工程提示 "Design file missing" / Flow-2001？**
A: 说明 `.pds` 里的相对路径从当前位置解析不到文件。检查 `source\rtl\` 是否和 `.pds` 在同一层。
本工程的 **96 个输入文件**（17 个 `.v` + 4 个 IP + 约束 + IP 内部源码）已全部核验存在，
`.pds` 里另外 24 个引用是 `synthesize/` `place_route/` `generate_bitstream/` 下的**编译产物**，
首次编译时自动生成，不需要预先存在。

**Q: 编译报 IP 相关错误？**
A: PDS 升级后 IP 需要重新生成。在 GUI 里双击 `source\rtl\pll\pll.idf`（以及另外 3 个 `.idf`）→ 重新 Generate。

**Q: PowerShell 不让运行脚本 / 执行策略报错？**
A: `build.bat` 调用的是 exe，不涉及 PowerShell 执行策略。如果你单独跑 `.ps1` 才会遇到。

**Q: 编译很慢？**
A: 完整流程 **约 4 分钟**（2026-10-16 实测 3 分 44 秒：综合 ~30s、布局布线 1m26s、时序报告 12s、生成比特流 19s）。
其中两次 `sdm2adm` 会刷大量 `Loop was found during constant probe` 警告，那是 DDR3 硬核 IP 内部的正常噪声，不用管。

**Q: 能用新版 PDS 吗？**
A: 可以，但跨版本打开会要求重新生成 IP。原例程是 2022.1 生成的，本机装的是 2022.2-SP6.1，
已在 2026-10-12 成功保存过一次，所以直接可用。

---

## 7. 与原始例程的差异

本工程相对 `D:\BaiduNetdiskDownload\HDMI_DDR3_OV5640_test\` 的改动：

1. **只保留源码和约束**，剔除了 100+ MB 的编译产物（`synthesize/` `place_route/` `report_timing/` `logbackup/` 等）
2. **`impl.tcl` 全部改为相对路径** —— 原文件写死了作者机器的 `C:/Users/w/Desktop/HDMI_DDR3_OV5647_test/...`，换机器就跑不了
3. **工程文件重命名为 `HDMI_DDR3_OV5640.pds`**（原 `.pds` 内部不含工程名字段，重命名安全）
4. 新增 `build.bat` 和本 README

原始的 `.pds` 本身是健康的（120 个引用全部存在、无绝对路径），之前编译失败是因为当时文件夹处于
`HDMI_DDR3_OV5640_test\HDMI_DDR3_OV5640_test\` 嵌套状态，`temp_projects` 里残留了旧路径。
