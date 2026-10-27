# S2：DDR 最小定向复现

日期：2026-10-19。结论：**当前主 RTL 的两个独立缺陷均已通过 RTL 仿真复现，申请 S3 最小修复；本轮不修复、不进入 S4。**

S1 准备工作收束。保留其硬件身份待确认项，但它们只阻止依赖具体器件/引脚/电压/物理时序的操作，不是独立 RTL 开发的全局前置条件。本轮没有重新盘点全工程，没有扩大旧 FPGA 最终感知/规则/显示架构。

## 1. 范围与当前状态

- 入口 `E:/FPGA drive`；主工程 `E:/FPGA drive/HDMI_DDR3_OV5640`；HEAD 重新读取为 `6f68d09149f3fcf3927174887f80cea9225fae50`。
- 重新检查入口、祖先及工程树的 AGENTS.md，没有发现适用文件。
- README 原有5行差异、原未跟踪文件及 S0/S1 报告保持；未修改 Git 索引、提交、移动或删除。
- 只新增独立驱动、定向测试台、证据复核脚本/说明和本报告；不改主 RTL/FDC/IP/PDS/build，不复制历史候选补丁。
- 实际使用 ModelSim SE-64 10.7，`D:/PDS/Modelsim/win64`；本次所需编译/加载/运行成功，不声称所有工具功能/许可证均已验收。

复用资产：

1. 原样复用 `E:/FPGA drive/_archive/experiments/road_video_ddr_20261017/tests/control_tb.sv`。
2. 阅读其 README、run_control.ps1、run.ps1、video_tb.sv、video_memory.sv、audit.py；旧驱动依赖搬迁前路径且默认运行候选版本，因此**没有执行旧驱动**。
3. rd_buf 新测试台复用 video_tb 的100MHz控制域、约37.1265MHz显示测试时钟、GTP_GRS启动、1280x720 / 1650x750激励、编号图样及NBA后采样方式，只保留单模块所需环境。

## 2. 首个最小用例：最后返回拍前有间隙

实际执行：

```powershell
& 'E:/FPGA drive/HDMI_DDR3_OV5640/tools/s2_ddr_minimal/run.ps1' -Case control
```

独立输出目录：

`E:/FPGA drive/tmp/s2_ddr_minimal/20261019_165654_671_915c3c3c_control`

编译对象仅为**当前主工程** `source/rtl/wr_cmd_trans.v` 和原归档测试台。虽然模块名包含 wr，测试的是它的 **read-return / rd_cmd_done 子通路**，不是写响应B通道。直接控制 `read_en`，总共80拍，在末拍之前额外停17个控制时钟，各拍之间原本还有2个空闲时钟；不经过 rd_ctrl/真实DDR，因此本用例不验证完整 burst 调度。

预先判定：80拍返回只允许一个与末拍返回对应的完成周期，没有返回时不得因为计数等于79就完成。

实际结果：

```text
CONTROL_RESULT premature=19 completion_cycles=20 accepted_returns=80
REJECT: premature/repeated line completion
```

ModelSim vlib/vlog/vsim退出码均0，运行至2800ns并正常 `$finish`，没有 Error/Fatal；驱动因 **DUT 功能失败** 返回1，不是工具受阻。

归档测试台输出的80是激励常量，所以另从原始 `control.vcd` 按时钟上升沿计数交叉核对，实际观测80个有效返回周期、20个完成高电平周期，其中19个没有返回。首次提前完成为2535ns，末拍实际返回为2725ns。这里是高电平占用了20个周期，**不是20个彼此独立的完成脉冲**。

定位证据：[wr_cmd_trans.v 第279行](E:/FPGA drive/HDMI_DDR3_OV5640/source/rtl/wr_cmd_trans.v:279) 只有read_en时推进数据计数，而 [第296行](E:/FPGA drive/HDMI_DDR3_OV5640/source/rtl/wr_cmd_trans.v:296) 只用计数==长度-1决定完成，没有使用当前返回有效条件。第79拍后计数停在79，空闲期间完成持续有效；这与本次波形一致。

受影响的当前连接：主 `wr_rd_ctrl_top` 的 rd_cmd_done 驱动帧缓存行完成；若下游按每个完成周期推进地址，会重复推进。该下游影响是连接/代码推导，**本用例本身没有重新仿真整个连接链**。

## 3. 单独验证 rd_buf：720行及末行

实际执行：

```powershell
& 'E:/FPGA drive/HDMI_DDR3_OV5640/tools/s2_ddr_minimal/run.ps1' -Case rd_buf
```

独立输出目录：

`E:/FPGA drive/tmp/s2_ddr_minimal/20261019_165834_892_82b1f9ec_rd_buf`

DUT仅使用当前主工程：

```text
source/rtl/rd_buf.v
source/rtl/rd_fram_buf/rd_fram_buf.v
source/rtl/rd_fram_buf/rtl/ipml_sdpram_v1_6_rd_fram_buf.v
```

保留原生成RAM实现，并实际加载安装目录的 `GTP_DRM18K.v`、`GTP_GRS.v`；不是理想FIFO替代。独立行级返回BFM对每次请求给80拍256bit数据，在最后数据拍被接收后给**恰一次**完成。**没有编译 wr_cmd_trans，也没有使用它的错误完成信号**，因此末行问题不依赖第2节缺陷。

用例包含原始全720行、每行1280像素，不裁边、不屏蔽末行；图样编码frame=1、x、y，逐像素对比全部921600个输出，原语未知值也算错误。

```text
RD_BUF_RESULT requests=719 completions=719 beats=57520
pixels=921600 errors=1280 last_row_errors=1280
missing_rows=1 address_errors=0 line_length_errors=0
REJECT: full-frame/last-row read incomplete
```

工具编译/加载/运行退出码均0；仿真正常结束于33,333,730,976ps。**功能判定失败**，驱动退出1。不是只看“有921600个DE像素”就判定帧有效。

| 检查 | 本次实际观测 |
| --- | --- |
| 行请求 | 719条，地址连续覆盖row0..718，缺row719；最后地址470300，缺少应有470580（十六进制原生地址） |
| 每行返回 | 已请求的719行各80拍，719次完成；57520拍只提供920320个像素，比完整帧少1280 |
| 输出 | 仍给921600个有效像素，但y719全1280像素错误，row0..718为0错误 |
| 首行/末行CSV | `0,1280,0,1`；`719,1280,1280,0`，列为row/pixels/errors/requests |
| 首个错误像素 | index920320、y719/x0，得到240f，期望97d4 |

定位证据：[rd_buf.v 第92行](E:/FPGA drive/HDMI_DDR3_OV5640/source/rtl/rd_buf.v:92) 由VS预取或有效行起点触发请求；[第96行](E:/FPGA drive/HDMI_DDR3_OV5640/source/rtl/rd_buf.v:96) 将wr_line复位成1，同时VS预取又计一次。计数提前到720，`wr_line != V_NUM` 抑制应有的最后预取，形成独立的少读一行问题。此次请求CSV和控制VCD与该解释对应；本轮没有将历史“置零”候选复制进来。

## 4. 证据、交叉检查与限制

| 证据 | 内容 |
| --- | --- |
| 两个运行目录的 `commands.json` | 实际命令、工作目录、UTC起止、退出码，不是计划命令 |
| `inputs_before/after.json` | 当前DUT、测试台、驱动、实际厂商原语模型SHA256 |
| `protected_before/after.json` | 本次已有源码/配置/主机/测试/工具/位流及Git索引保护；前后相同 |
| `compile.log`、`simulation.log`、`console.log` | 真正RTL编译/加载/运行记录；没有软件参考冒充RTL |
| `control.vcd`、`rd_buf_control.vcd` | 第一个用例全层级波形、第二个行请求/地址/计数/完成控制波形 |
| rd_buf的 `requests.csv`、`rows.csv`、`mismatches.csv` | 全行请求和全行错误计数；mismatches仅保留前16个像素详情，不是全部错误列表 |
| 两个目录的 `result.json`、`evidence_manifest.json` | 分离工具成功与DUT失败，输入/保护一致，证据哈希 |
| `E:/FPGA drive/tmp/s2_ddr_minimal/evidence_review_20261019_170218_817.json` | 波形80/20/19计数、CSV719请求/720坐标行/末行错误、证据哈希及S1原293个保护文件复核一致 |

最小DUT输入指纹：

```text
wr_cmd_trans.v CCAA77338301EF6416F48B7AACDD6881BF5E8970D1E0575C41E45B79F826CA86
rd_buf.v       E211CB731DE0D433A2D79A919CF45FCE47A5828C7E84191D6F5543909B6CEDC4
```

限制与未验证：

- 第二个用例有17条原始警告，含 `-novopt` 和厂商RAM未连接WWCONF/端口数提示；未隐藏后两类警告、未修改IP。仿真0 Error/Fatal不意味着所有警告可永久忽略。
- 第二个用例的row像素计数按输出序列每1280像素分组，并非独立DE包络时序断言；但请求地址/行号独立记录，全部像素有编号金标准。`line_length_errors=0`不能扩大解读为完整视频IO时序通过。
- 首版 `requests.csv` 的 `time_ns` 表头单位误标，`%0t` 实际按1ps精度输出；应按ps/VCD timescale解释。原始证据保留，行/地址/数据和完成判定不依赖该表头。
- 仅测试一个定向80返回激励和一个孤立完整帧；没有覆盖全部间隙位置、连续多帧、各种异步相位、复位/停流/背压/帧所有权。
- 返回BFM不是DDR控制器/PHY/电气模型；尚未验证真实颗粒、训练、物理带宽、综合、PNR/STA或上板。
- S1的两份交付文档及原293文件保持原哈希；没有把旧时序结论升级为本轮通过。没有工具阻塞。

## 5. 改动与下一步

新增文件：

```text
E:/code/core-portal/HDMI_DDR3_OV5640/tools/s2_ddr_minimal/run.ps1
E:/code/core-portal/HDMI_DDR3_OV5640/tools/s2_ddr_minimal/rd_buf_full_frame_tb.sv
E:/code/core-portal/HDMI_DDR3_OV5640/tools/s2_ddr_minimal/verify_evidence.ps1
E:/code/core-portal/HDMI_DDR3_OV5640/tools/s2_ddr_minimal/README.md
E:/code/core-portal/HDMI_DDR3_OV5640/docs/reintegration/04_ddr_minimal_reproduction.md
```

其他新增仅为独立tmp输出与证据，不是构建输入；原归档、旧产物和S1快照均未改写。

**申请下一轮仅执行S3a：修复 wr_cmd_trans 的末拍有效完成条件，并以本用例从20/19失败转为1/0通过为首要验收。**随后扩大零间隙/不同间隙/多次命令/复位等单元回归，保持修改范围单一，不顺带修rd_buf。

S3a通过后，再单独授权S3b修复rd_buf行计数/预取边界，以720请求、57600返回拍、921600像素全对、y719零错误为门槛。不得以屏蔽末行或改预期绕过。证据复核脚本当前是“已复现失败”的核对器，不应把它的EvidenceConsistent误当作修复验收通过。

这两项明确缺陷存在，本轮不提出跳过修复直接进入S4。以后进入S4的最小条件是：这些阻塞缺陷的局部修复与相应回归通过，先确定干净主图接入点和像素/DE/SOF对齐的可测试契约，再小步开发；**不要求所有硬件身份或全IO签核先完成**。实际改引脚、电压、PLL/DDR IP或安排上板时，才核对各自依赖的实物证据。

本轮到定向复现及记录结束，未自动执行S3或其他阶段。
