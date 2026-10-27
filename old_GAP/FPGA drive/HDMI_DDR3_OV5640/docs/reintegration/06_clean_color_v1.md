# V1 干净彩色主图 / S4

日期：2026-10-19。用户授权：本轮修改、定向检查、由代理运行PDS完整编译；
用户手动下载。本轮不执行JTAG、Flash、网络、双目或最终识别开发。

## 1. 本版做什么

```text
CMOS1 / 既有RGB565转换
  -> img_proc原有彩色行缓存
  -> c_pix[15:0] / c_pix[16] / window_vs
  -> 新增同拍寄存的 clean_rgb_out / clean_de_out / clean_vs_out
  -> 原fram_buf / DDR（保留S3a、S3b）
  -> 原读出与HDMI RGB888扩展

同一彩色缓存 -> 原候选 / 斑马线 / 几何 / HUD -> 原rgb_out/de_out/vs_out
                                               （不再接入主DDR）
```

正常主路不经过候选着色、斑马线框、边界绘制或HUD。
不是把MODE改成0：顶层仍保留原MODE4、ZEBRA_ENABLE1、ADAS_ENABLE1诊断配置及源码，
但其输出不进入DDR。PDS可优化掉无消费者的诊断逻辑。
原接口仍可单元测试/另行接入诊断支路；本版没有新增按键切换、运行时诊断显示或并行第二显示口，
也不应为恢复旧显示而将处理后的像素混入正式彩色主图。

干净流来自原有行缓存，**不是传感器DVP直接旁路**。
它的DE、VS独立于旧lane/HUD流水延迟；不得交叉搭配。
VS为跟随缓存数据的一拍标记，在首个有效像素前一拍；
端到端仍含行等待及末行flush，不是固定一拍延迟。

## 2. 改动与保留

| 文件 | 本轮变更 |
| --- | --- |
| `source/rtl/img_proc.v` | 新增3个clean输出，在所有绘制之前取底图，数据/DE/VS同拍寄存并在复位时清零；不重写旧窗口/绘制算法 |
| `source/rtl/hdmi_ddr_ov5640_top.v` | DDR写入口改接clean三元组；img_rstn跟随实际选中相机配置完成信号，不再OR两路；移除本地总是开启且没有有效旁路的USE_IMG_PROC宏壳 |
| `tools/s4_clean_video/clean_video_tb.sv` | 全幅及诊断隔离RTL回归 |
| `tools/s4_clean_video/run.ps1` | 独立ModelSim运行、输入哈希和结果采集 |
| `tools/s4_clean_video/build.ps1` | 独立构建副本、同一flow、PDS完整构建、输入保护及位流身份记录，无下载命令 |
| `tools/s4_clean_video/README.md` | 运行入口和验证边界 |
| 本文、`07_video_interface.md`、`docs/development/project_context.md` | 实现/构建/上板交接及历史草案状态路由 |

Git HEAD仍为 `6f68d09149f3fcf3927174887f80cea9225fae50`，修复与V1都在工作副本中，未提交/暂存。
原README及其他用户改动不回滚。未重做全工程审查或备份；本轮输入副本只用于隔离构建。
引脚、FDC、PLL、DDR参数/IP、相机寄存器、HDMI时序、工程设计文件列表和flow模板不改。

本版两个生产文件SHA256：

```text
img_proc.v             B77637F60F0B9F297692A236173125D76F9B561FB4743CE963DB914C0F19C833
hdmi_ddr_ov5640_top.v  8D226F7501DBB0147AE9AC3F7FD01B755ED7C87B407C0BBC5D3CC94E25DE5878
```

S3a / S3b文件哈希仍与 `05_ddr_correctness_fix.md` 相同。
用户已反馈上一版编译、下载及旧功能基本正常；这是用户反馈，不代替V1实物验收或全IO签核。

## 3. 定向检查：已执行

```powershell
& './tools/s4_clean_video/run.ps1'
git -c core.whitespace=cr-at-eol diff --check
```

第二条适配既有顶层CRLF；不改原文件换行风格或Git配置。

| 用例 | 实际结果 |
| --- | --- |
| 6个1280x720完整帧 | 5529600像素、零错误；红/绿/蓝、1像素棋盘、行列编号/四边哨兵、帧标记图样 |
| 行/帧检查 | 4320行CSV逐项核查：每行1280像素、零错误；每帧首末行均包含 |
| 复位/启动 | 启动未见VS的输入不输出；第三/第四帧间复位，32个复位采样点clean输出全零，后续帧正确 |
| 诊断隔离 | 两个1280x72帧，共184320像素；诊断开/关的clean三元组逐拍一致（包括消隐），旧诊断输出23808像素被实际改变 |
| 原提前同步用例 | 原测试台未修改，3个1280x13帧、49920像素保持不变，PASS |
| 输入保护 | 定向仿真输入在运行期间不变；DDR两处修复哈希保持不变 |

成功仿真：
`E:/FPGA drive/tmp/s4_clean_video/20261019_180203_403_d7ac07a1/`。
内含 `result.json`、`cases.json`、`commands.json`、输入前后哈希，各用例子目录的
`simulation.log`，以及新用例的 `rows.csv` / `frames.csv`。
编译0 Error；测试台省略的未使用输出产生端口连接告警，日志保留。

初次运行：
`E:/FPGA drive/tmp/s4_clean_video/20261019_180102_250_0dccbc90/`。
因脚本将物理路径误作ModelSim逻辑库名，设计加载失败，未执行RTL。
修正为每用例明确映射 `work` 后使用新目录重跑成功，没有为此修改生产RTL或预期图样。

本轮没有重跑全部旧算法、全DDR/PHY仿真，也没有把内部规范RGB565纯色验收称为相机原始字节/色序实测。

## 4. PDS构建

实际调用：

```powershell
& './tools/s4_clean_video/build.ps1' -SimulationResult 'E:/FPGA drive/tmp/s4_clean_video/20261019_180203_403_d7ac07a1/result.json'
```

独立运行目录：
`E:/FPGA drive/tmp/s4_clean_video_build/20261019_180417_522_1f1e00a2/`。
PDS `D:/PDS/PDS_2022.2-SP6.1/bin/pds_shell.exe -file build.tcl -continue`，
完整沿用 `flow.tcl` 的Compile/Synthesize/Map/PNR/Timing/Bitstream命令。
原工程根目录的旧SBIT、时序报告和已有PDS会话不触碰。

实际结果：PDS退出码0，Compile、Synthesize、Device Map、PNR、独立Report Timing、
Generate Bitstream均完成，最终验证 `result.json` 为PASS。
完整构建工具报告耗时约5分10秒；无下载或固化。
当前源目录、FDC/工程/flow及构建副本的输入指纹均不变，见 `input_changes.json`（两项为空）。

最终独立时序报告：
`report_timing/hdmi_ddr_ov5640_top.rtr`，
`Design Summary : All Constraints Met.`。
快慢角setup/hold摘要的失败端点均为0：

| 项目 | 最差裕量 |
| --- | --- |
| Setup / Slow | +1.692 ns |
| Setup / Fast | +1.834 ns |
| Hold / Slow | +0.216 ns |
| Hold / Fast | +0.137 ns |

必须保留的工具信息及边界：

- PNR日志有 `Hold violation fix failed. (takes 99.62 sec).` 子步骤信息；
  随后PNR命令报告成功，最终独立STA仍全部满足现有约束。
  不把该信息删除，也不因这一行盲目继续修约束/DDR；本轮未进一步归因其内部优化终止条件。
- 原有 `STA-3011` no-clock配置链告警仍在；`clk_25M`显式约束0负载、
  CLKOUT2推导时钟有负载等覆盖限制仍存在，故**不是全IO/CDC签核或零告警构建**。
- 综合网表保留clean流，未发现 `u_img_proc/u_lane`、`g_adas`、`g_zebra`诊断层级，
  符合无消费者诊断支路可被优化的预期；诊断算法源码未删除。

最终手动下载文件：

```text
E:/src/inventory-dashboard/tmp/s4_clean_video_build/20261019_180417_522_1f1e00a2/V1_clean_color_cmos1.sbit
大小：2101696 bytes
SHA256：D9C3A6D50289F7BFD8BBF28EA5205FCDCE8F194B01058F5547405592A7A44951
```

位流实际生成于本地18:09:30，晚于本轮18:04:19开始；
`release.json`记录副本身份，与 `generate_bitstream/hdmi_ddr_ov5640_top.sbit` 哈希相同。
构建源码、工具/流程、日志、完整阶段产物均保留在上述独立目录；本文件不是仅保存一个哈希。

### 交付脚本误报及复核

第一次交付校验误报 `Bitstream predates this build.`，
原因是 `[DateTime]::Parse` 把带Z的开始时间转成本地时间后直接与UTC时间比较。
不是PDS失败、旧位流或RTL失败。修正为
`[DateTimeOffset]::Parse(...).UtcDateTime` 后，仅重做产物/哈希/时序验证，没有再次运行PDS：

```powershell
& './tools/s4_clean_video/build.ps1' -SimulationResult 'E:/FPGA drive/tmp/s4_clean_video/20261019_180203_403_d7ac07a1/result.json' -VerifyCompletedRun 'E:/FPGA drive/tmp/s4_clean_video_build/20261019_180417_522_1f1e00a2'
```

原误报保存在 `result_before_verification_20261019_181149_882.json`；
`verification.json`明确记录 `PdsRerun=false`、复核脚本SHA256和时间。
最终 `result.json`、`release.json`来自这次成功复核，不改文件时间来“制造”通过。

## 5. 用户手动上板验收

本版未下载/固化。最终只采用本次独立目录中经 `release.json` 绑定的
`V1_clean_color_cmos1.sbit`，不选仓库根 `generate_bitstream` 或 `bitstreams` 的旧文件。

原工程入口仍为：
`E:/FPGA drive/HDMI_DDR3_OV5640/HDMI_DDR3_OV5640.pds`；
顶层 `hdmi_ddr_ov5640_top`，不需要添加设计源文件或测试台。

1. 沿用上一版可工作的供电、摄像头模组/排线、HDMI OUT及JTAG接线，不改电气连接。
2. 在下载器重新选择本次新SBIT绝对路径，记录下载结果；用户操作下载，代理不执行。
3. 正常：显示CMOS1实时彩色，没有`EXPERIMENT / NO PAIR`文字、
   人工绿/青候选涂色、车道线或斑马线框。真实物体本身的绿色当然保留。
4. 用红、绿、蓝物体/色卡检查明显的通道交换；拍摄棋盘/带编号图案，
   检查首末行列、底部和移动时是否错位/冻结。实拍不是精确数字纯色金标准。
5. 连续观察约1分钟并再次JTAG配置同一新SBIT，看是否能恢复。
   若断电后从旧Flash启动，需要重新JTAG下载本版，不能把旧HUD归咎于V1。
6. 反馈全画面、底部近照、约10秒移动视频、色卡原图/实拍对照、
   下载路径/结果、是否裁边或过扫描、异常发生时间和重配是否恢复。

失败/待查：仍有旧HUD（先核对位流）、红蓝明显互换、缺首末边、固定杂色条、
持续冻帧/撕裂/黑屏、重新配置无法恢复。显示设备裁边时，末行应记为肉眼不可判定。

## 6. 边界与停止

V1是干净彩色像素流与DDR接入，不是完整的新帧管理协议。
采集frame_id/session、坏帧丢弃、完整帧发布、缓冲归属、停钟检测和网络背压等，
仍按对应后续任务逐项实现/验收；不把S1草案全部字段写成已交付。
原始DVP奇数字节/异常HREF配对、所有异常复位、真实颜色/尺寸/帧率及长稳仍未据此证明。
旧FDC/推导时钟的覆盖限制如实保留，不为本轮通过修改约束或放宽时序。

完成本版构建与交接后停止，等待用户V1上板反馈。下一阶段是S5网口小包双向链路，
不是本轮顺带发送图像、调最终识别算法或扩展多路输入。
