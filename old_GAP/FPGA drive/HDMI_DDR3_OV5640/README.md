# 🚗 紫光同创 FPGA · 高级辅助驾驶系统

> 基于 **盘古 50K（PGL50H）** 的实时视频感知流水线
> 全国大学生嵌入式芯片与系统设计竞赛 · FPGA 创新设计赛道 · 紫光同创选题三

当前开发入口：[项目进程](E:/FPGA drive/HDMI_DDR3_OV5640/reports/项目进程.md)、
[单路ETH1接线与实施边界](E:/FPGA drive/HDMI_DDR3_OV5640/reports/单路高速互连方案_2026-10-18.md)。
按比赛功能闭环优先推进；v11仅合成规则四键交互通过，v12手工修复停止。
下文旧构建/下载命令不是本次执行授权；当前不改RTL、不综合/映射、不烧录。

---

## ⚙️ 硬件

| | |
|---|---|
| 芯片 | PGL50H-6FBG484 |
| 开发板 | 盘古 50K（小眼睛科技 MES50HP） |
| 工具链 | PDS 2022.2-SP6.1 |
| 摄像头 | OV5640 ×1，DVP 8bit，接 CMOS1 |
| 输出 | HDMI 1280×720 |

---

## 🔄 数据流

```
OV5640 ──► RGB565 ──► img_proc ──► fram_buf ──► DDR3 ──► HDMI
                          │
                          ├─ 灰度化
                          ├─ 3×3 中值滤波
                          ├─ Sobel 边缘
                          ├─ 车道线跟踪
                          ├─ 斑马线候选
                          └─ ADAS HUD 叠加
```

---

## 📦 主要模块

| 文件 | 作用 |
|---|---|
| `img_proc.v` | 图像流水线总控，灰度 / 中值 / Sobel / 叠加 |
| `lane_detect.v` | 车道线跟踪，\|Gx\| > 2\|Gy\| 方向过滤 |
| `lane_geometry.v` | 车道几何计算 |
| `zebra_detect.v` | 斑马线候选检测 |
| `adas_overlay.v` | HUD 叠加层 |
| `adas_packet.v` | 结果数据包 |
| `adas_test_pattern.v` | 内置自检图源（六场景轮播） |
| `fram_buf.v` + `DDR3_50H` | 帧缓存 |
| `cmos_8_16bit.v` | DVP 8bit → RGB565 |

---

## 🔨 编译

双击 **`build.bat`** 即可。

```powershell
# 或手动
pds_shell.exe -file impl.tcl -continue
```

产物：`generate_bitstream/hdmi_ddr_ov5640_top.sbit`

> ⚠️ 不要手改 `impl.tcl` —— PDS 会把绝对路径流程追加到脚本末尾。
> 要改流程请改 **`flow.tcl`**，`build.bat` 每次从它重新生成。

---

## 🔥 烧录

挑 `bitstreams/` 里对应功能的文件：

PDS → `Tools` → `Configuration` → `Boundary Scan` → 右键 `Initialize JTAG chain` → 右键器件 `Program...`

---

## ✅ 现在能做什么

- 摄像头实时采集 → DDR3 缓存 → HDMI 显示，全闭环
- 灰度 / 3×3 中值 / Sobel 边缘三种画面
- 原图 + 红色边缘 + 绿色车道线叠加
- 车道线逐行跟踪，锁定后跟随镜头晃动
- 斑马线候选（重复白条 + 连续帧确认）
- 内置自检图源，不接摄像头也能验证 DDR / HDMI
- 电脑端 Python / C 结果协议接收

---

## ❌ 还没做什么

| 缺口 | 说明 |
|---|---|
| FPGA ↔ ARM 真实链路 | 协议只跑在电脑上，没有实体接口 |
| 行人 / 障碍物识别 | 未实现 |
| 真实车速和距离 | 电脑端是软件模拟 |
| 四路视频 | 只做单路 CMOS1 |
| 双目测距 | 两个摄像头接口都在，但没做同步 |

**不能声称赛题基础任务已全部完成。**

---

## ⚠️ 许可证

PDS 许可证**绑定本机 ID，即将到期**，比赛提交前一天失效。

**必须在截止前重新申请**，否则最后一版代码编译不了。

---

## 🗂️ 归档

历史快照（v4–v12、各类实验）已移出仓库，放在：

```
E:\FPGA drive\_archive\experiments
```

仓库只保留可编译、可复现的内容 👌
