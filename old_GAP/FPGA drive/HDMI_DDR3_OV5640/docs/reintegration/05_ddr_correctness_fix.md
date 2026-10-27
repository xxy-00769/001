# S3a / S3b DDR 正确性修复交付

日期：2026-10-19。范围：保留侧会话 S3a，实施 S3b 最小修复及定向 RTL 仿真。
本版未综合、映射、布局布线、生成位流、下载、固化或上板；没有新增干净彩色出口或网络功能。
不修改引脚、FDC、PLL、DDR 参数、IP、工程文件、构建脚本或 v12。

## 1. 版本与修改

工程根：`E:/FPGA drive/HDMI_DDR3_OV5640`。
本轮开始重新读取 Git 状态：`main...origin/main`，
HEAD `6f68d09149f3fcf3927174887f80cea9225fae50`。
原有 `README.md` 修改、S3a 修改、未跟踪资料/工具及仓库外归档保留；未暂存、提交或清理。
这是 HEAD 上的工作副本修复，HEAD 本身不包含这两行修复。

| 文件 | 行为与归属 |
| --- | --- |
| `source/rtl/wr_cmd_trans.v:296` | 侧会话 S3a 已改：`if(read_en && rd_data_cnt == rd_trans_len - 1'b1)`。只有最后一拍有效返回才产生完成，等待末拍的间隙不再提前/持续报完成；本轮未再次修改 |
| `source/rtl/rd_buf.v:97` | 本轮 S3b：`wr_line <= 12'd1` 改为 `12'd0`。帧同步预取首行本身会增加计数，原先初值1重复计入一行，使720行只发719次请求；改为从0计数后覆盖末行 |
| `tools/s3a_wr_completion/{regression_tb.sv,run.ps1}` | 保留侧会话的16项回归，不重写 |
| `tools/s3b_rd_buf/{regression_tb.sv,run.ps1,README.md}` | 新增连续帧/帧间复位回归与运行入口；不加入PDS |
| 本文件、`docs/development/project_context.md` | 补齐S3a结果，登记S3b及用户编译/上板交接 |

生产 RTL SHA256：

```text
wr_cmd_trans.v  2B99C581904A5C61FAA6EA8BF06065482A724A72C01CB4EF56FE86E53443F659
rd_buf.v        E2E4D26D2C84405B62A17C749CA00138BC438975A14992F5A920B99D0CCB8635
```

## 2. 实际检查与证据

### S3a：复用侧会话实测结果

本轮读取两份 `result.json`、回归日志，并逐项核对其输入哈希。
当前 `wr_cmd_trans.v`、S3a测试台/脚本、原复现测试台及S2脚本均匹配已有PASS证据。
S3b不依赖更改该模块，本轮没有重跑S3a。

- 原复现：80拍返回，完成1周期，提前完成0周期，PASS。
- 16项RTL回归：16条命令、1092拍返回、13次完成、3711项检查、零错误，PASS。
  其中3条命令主动中止，因此不应有16次完成。
- 覆盖连续返回、多种/随机间隙、末拍长间隙、不同长度、连续命令，以及0/37/79拍后复位再执行。
- 原复现证据：
  `E:/FPGA drive/tmp/s3a_wr_completion_original_case/20261019_171049_737_2376748f_control/`
- 16项证据：
  `E:/FPGA drive/tmp/s3a_wr_completion/20261019_171119_771_58524eda/`
  内含 `result.json`、`simulation.log`、`inputs.json`、`cases.csv`、`commands.json`。

### S3b：本轮执行

实际执行原S2入口，未改原测试台、预期图样或RAM：

```powershell
& './tools/s2_ddr_minimal/run.ps1' -Case rd_buf -OutputParent 'E:/FPGA drive/tmp/s3b_rd_buf_original_case'
& './tools/s3b_rd_buf/run.ps1'
```

原用例PASS：720次请求、720次完成、57600拍返回、921600像素；
像素错误、末行错误、缺行、地址错误、行长度错误均为0。
`rows.csv` 中 y=719 为1280像素、0错误、1次请求。
输入/受保护文件在运行期间哈希不变。

原用例证据：
`E:/FPGA drive/tmp/s3b_rd_buf_original_case/20261019_171804_790_dffb606c_rd_buf/`。
包含 `result.json`、`rows.csv`、`requests.csv`、`simulation.log`、
`inputs_before.json` / `inputs_after.json`、命令及控制VCD。

新增回归PASS：先连续两帧，再在帧间拉低 `ddr_rstn` 后执行第三帧。
每帧使用不同图样标记，保持原RGB565预期算法和全幅范围。
每帧均为720次请求、720次完成、57600拍、921600像素、零像素错误及零末行错误；
额外检查每行恰好请求一次，以及720段实际DE、每段1280像素。
累计2160次请求/完成、172800拍、2764800像素，零错误；输入哈希运行期间不变。

新增回归证据：
`E:/FPGA drive/tmp/s3b_rd_buf/20261019_172032_269_ab1448a2/`。
`frames.csv` 逐帧记录复位标记和所有指标，`rows.csv` 含3帧共2160行；
`requests.csv`、`simulation.log`、`control.vcd`、输入哈希、命令与 `result.json` 同目录保留。
既有帧bank计数不由 `ddr_rstn` 清零；回归按其原有生命周期检查交替地址，
没有为使复位用例通过而修改bank规则。

两次S3b仿真摘要均为0 Error、17 Warnings；
日志保留 `-novopt` 弃用提示及现有RAM端口连接告警，没有静默改IP消除告警。
另执行 `git diff --check`，通过。
收尾复核三帧共2160行CSV，所有行均为1280像素、0错误、1次请求；
当前7个回归输入文件哈希与运行后记录一致。
对照S3a原复现留存指纹，选取顶层、S3a生产RTL、工程/构建/FDC及相关PLL/DDR/行RAM资产共198个文件，
当前哈希全部一致；本轮生产改动仅为 `rd_buf.v` 的上述一行。
只核对相关源码/配置差异及证据一致性，不重做全工程审查。

仿真保留真实Pango行RAM原语；DDR侧只是逐请求提供80拍的native-return BFM，
不是完整DDR控制器/PHY仿真，也不是两处修复的整机集成验证。
现有生成RAM与安装的原语接口有 `WWCONF` 未连接告警，日志保留，不改IP。
本轮不证明最慢返回/带宽边界、仲裁、帧所有权、中途断流或中途复位恢复。
旧S2失败证据保持不动；`verify_evidence.ps1` 是旧失败证据的一致性检查，不是修复后验收入口。

## 3. 打开与编译

打开：
`E:/FPGA drive/HDMI_DDR3_OV5640/HDMI_DDR3_OV5640.pds`

顶层：`hdmi_ddr_ov5640_top`。
PDS及 `flow.tcl` 已包含 `rd_buf.v`、`wr_cmd_trans.v`，无需添加工程文件。
**不要把 tools 下测试台加入PDS。** 保持当前器件、约束及IP设置，不套用归档v12配置。

用户在PDS中从 Compile 起强制重跑，而非复用旧综合/布局布线检查点：
Compile -> Synthesize -> Device Map -> Place & Route -> Report Timing -> Generate Bitstream。
每阶段确认实际成功，保留本轮日志，检查setup/hold、有效时钟与未约束路径；
不能仅以生成了文件或局部 `All Constraints Met` 判定通过。

如果使用现有 `build.bat`，它从 `flow.tcl` 生成 `impl.tcl` 并执行完整构建，
还会删除通用旧SBIT。因此先另存需要保留的旧SBIT/日志，不要把它当“只检查”入口。
其脚本只按SBIT是否存在显示OK，仍须人工检查每阶段日志和时序报告。
本轮仅只读这些配置，没有执行上述任何构建操作。

### 确认下载的是本轮新位流

1. 构建前记录开始时间；保留旧位流后，从Compile强制重新执行全部阶段。
2. 检查日志中顶层和工程绝对路径正确，输入是本文件第1节哈希对应的生产RTL。
3. 只有完整构建成功后才采用：
   `E:/FPGA drive/HDMI_DDR3_OV5640/generate_bitstream/hdmi_ddr_ov5640_top.sbit`。
   它的修改时间必须晚于本轮构建开始时间；核对日志中的成功生成记录和同一输出路径。
4. 记录下列只读信息，并在下载器中重新选择这个绝对路径，核对截图。
   不选 `bitstreams/` 内旧命名SBIT或归档v11/v12位流。

```powershell
Get-Item -LiteralPath 'E:/FPGA drive/HDMI_DDR3_OV5640/generate_bitstream/hdmi_ddr_ov5640_top.sbit' |
    Select-Object FullName,Length,LastWriteTime
Get-FileHash -LiteralPath 'E:/FPGA drive/HDMI_DDR3_OV5640/generate_bitstream/hdmi_ddr_ov5640_top.sbit' -Algorithm SHA256
```

本版没有版本寄存器或新增可见版本标记，不能靠画面/HUD文字识别新位流。
日志、文件时间、哈希和下载路径共同绑定版本。先做JTAG易失下载，不需要本轮固化Flash。
断电会丢失JTAG配置；若断电后从旧Flash启动，必须重新下载本轮SBIT才能继续测试本版。

## 4. 用户上板测试

沿用此前可工作的同一板卡、原配供电、双目模组与已核对排线方向，不改电源或IO接线。
本版 `CMOS_1` 有效、`SELF_TEST=0`，只选择模组CMOS1进入主图，并非双目并行。
FPGA板的 **HDMI OUT** 接显示器或采集卡的HDMI输入；
JTAG沿用已工作的下载连接。本轮不要求网线、香橙派或新增接线。
未知板号/电压等仍只阻止相应换线/参数操作，不阻止这次独立修复。

有限测试步骤：

1. 下载后观察初始化和实时画面。保持当前旧检测/HUD配置，不能要求显示纯净彩色。
   相关初始化/心跳LED可拍照辅助排查，但不按未知极性判定，也不当作像素正确证明。
2. 持续观察约1分钟，并让摄像头前的物体移动。
   正常是实时更新、不持续冻结/撕裂；特别检查画面底部是否固定出现上一行/旧内容、杂色条或缺行。
3. 为了看清底部，用高对比横纹/带行编号图案放入摄像头视野，录制包含整个画面边缘的视频。
   显示器关闭过扫描；有条件使用原始1280x720采集截图并放大底部。
   若设备会裁边，标为“末行肉眼不可判定”，不要写末行通过。
4. 再次JTAG配置同一新SBIT，确认重新初始化后仍恢复画面。
   如果另做整板断电重启，记录是否重新JTAG下载，区分旧Flash启动。

失败现象：无信号、黑屏、初始化不恢复、持续冻帧、整图重复错位/撕裂，
或底部固定错误/旧行；请记录从下载到故障的时间及复现动作。
摄像头画面/HUD本身会影响底部内容，不能单凭肉眼声称已精确验证y=719的1280像素。
精确逐像素末行验收目前来自RTL仿真，上板是另一等级证据。
当前没有新增可读帧/行统计、寄存器或通信查询，不要求读取不存在的参数。

## 5. 请反馈与停止点

- 构建失败：具体阶段、首个Error及前后上下文、完整相关日志；不要只发最后的“失败”。
- 构建成功：综合/资源摘要，最新 `report_timing/hdmi_ddr_ov5640_top.rtr`，
  setup/hold摘要及最差路径、时钟/未约束警告；若报告路径不同，提供实际路径。
- 下载：选中的SBIT完整路径、大小/修改时间/SHA256，下载结果截图。
- 实物：全画面及底部原始截图、约10秒移动画面录像、是否裁边、连接/重配步骤和故障时间。
  没有问题也请说明持续观察时长、是否再次配置及恢复情况。

本轮到DDR修复交付停止。下一功能版本为V1干净彩色主图：
沿用现有采集/DDR/HDMI，让正常路径不调用候选涂色及HUD，旧检测保留诊断配置。
这是下一轮任务，不在本版提前修改。
