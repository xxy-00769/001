# MPI7001 V5.1 显示排查与修正候选

## 证据与范围

2026-10-20，用户烧录 V5 后照片显示有输入画面，但明显错块、偏色及绿色杂点。V5 显示验收失败。原包移动至 `E:/zhoumian/FPGA/JF/V5_MPI7001_800x480`，位流 SHA256 为 `0C6CCBEF63A9BD61BFFD4B97CAC1756F8255CD6FF483814F0AE671A9A54D66A4`。后续构建和交付采用英文路径。

本轮仅改显示适配及相关时钟连接，不改摄像头格式、采集、算法、DDR 写入、所有权及 KEY8 六档。修复可复现的输出缺陷，并增加上板定位手段。持续错块根因未确认，不能声称最终修复或上板成功。

修改前备份：`E:/zhoumian/FPGA/tmp/v5_1_baseline_20261020_132132`。已有 Git 修改和原 V5 全部保留。

现场照片另存为 `E:/zhoumian/FPGA/JF/checks/v5_field_feedback_20261020/corrupted_display.jpg`，仅证明用户提供的可见症状，不证明内部数据链的具体故障点。

用户随后补充：V4 及更早代码在普通显示器上均能正常显示。这是可用基线的现场证据，应优先排查 V5 新增的缩小读出、面板时序、时钟连接及新实现相关差异；不应据本轮 Icarus 夹具的首拍未知值就认定原采集/写 DDR 已坏。本轮继续保持原采集和算法不变。该对比还不是同一位流在两个显示器上的 A/B 测量，不能单独排除某一层。

用户进一步明确“直接改显示模块，算法不用检查”。此后停止算法/原写侧的功能排查，工作限定于显示时钟、时序、读出和输出数据对齐。PDS 自动整板时序验收仍是生成交付位流的必要检查，其中出现旧模块名不代表正在修改或验收算法功能。

## 发现与处理

### 首帧同步缺陷：已复现并修正

V5 时序模块复位时纵计数器为零，直接输出 `v < 3`，读侧同步寄存器会提前记住高电平。复位解除后没有新的上升沿，可能遗漏首帧预取与读指针初始化。

旧 reader 测试在时序模块启动前人为发送一个帧脉冲，绕过了实际连接的这一问题。本轮取消人工脉冲，直接连接时序源；修改前首像素失败：`got=xxxx expected=15a7`。保留证据 `E:/zhoumian/FPGA/old_GAP/FPGA drive/tmp/v5_startup_before/test.log`。

最小修复为 `frame_sync = rst_n && v < 3`，复位时保持低电平，启动产生实际 SOF。该缺陷解释启动异常，不足以单独解释照片中的持续错块。

### 时钟结构：最终保留 V5，拆分候选未采用

曾构建独立 PLL 候选，试图恢复 V4 配置/25MHz 输出并为显示增加独立 PLL；没有现场证据证明这能解决持续花屏。用户进一步要求仅改显示模块后撤销此候选，最终保持 V5 的 `pll_mpi7001 u_pll`、29.545454MHz 像素/10MHz 配置/25MHz 控制输出，FDC 也恢复 V5 版本。交付不包含额外 PLL 或配置时钟恢复。

25MHz 在本工程用于既有摄像头配置/控制，不能把它直接说成传感器 PCLK。没有改变时序约束或隐藏路径。

### HDMI 边沿保持不变

本地 `MS7210 Register Map.pdf` 第 9–10 页说明 `0x1281 bit2` 为时钟反相，现有驱动首条写入 `0x1281=0x04`。不能仅凭 RGB 在上升沿更新就断言接收端也在同边沿采样。本轮没有盲目改为下降沿，也没有改芯片初始化。

依据：`E:/zhoumian/FPGA/资料/盘古50K开发板资料/MES50H-HDMI视频板/ic_datasheet/HDMI PHY/MS7210 Register Map.pdf`。文档与代码检查不是现场寄存器读回或实测信号。

### 输出独立检查图案

屏幕 y=8..39 为八段 100 像素宽的白/黄/青/绿/紫/红/蓝/黑色条，y=440..471 为逐像素黑白棋盘。其 RGB 与面板 HS/VS/DE 同延迟两周期，再经过原有输出寄存器。中央 x=80..719、y=60..419 摄像头区域保留。

检查图案不经过摄像头、算法、DDR 或 KEY8。色条干净、中央花屏时优先查上游数据链；色条自身异常时优先查最终输出与外部连接。此方法缩小范围，不单凭一个现象判定根因。细棋盘可能因缩放或拍摄产生摩尔纹。

## 验证及限制

- 时序测试：复位无 SOF、首帧 SOF、三整帧几何/极性/延迟及全部检查图案坐标。
- PLL 原厂模型：V5 像素、配置、25MHz 控制时钟及锁定；最终使用单 PLL 的测试记录。
- 独立 reader：无人工启动脉冲，两整帧 460800 像素、隔行隔列地址、末行及循环 RAM 回绕。
- 新 native reader：生产 `rd_buf`、`wr_rd_ctrl_top`、`wr_cmd_trans`、`rd_ctrl`，只在 DDR native 边界用实际地址生成返回数据，加入突发间及返回拍间等待，逐像素检查两整帧。不包含 writer 或所有权。
- Icarus 仍使用已记录的临时 RAM 兼容副本：仅 CSA/CSB 常量组合块改为 `always_comb`，保留原厂 `GTP_DRM18K`。生产 IP 未改。
- 旧集成写侧夹具局部观察到首写突发首拍未知值，后续拍为已知图案；此路径未完成定位或验收，不能声称完整摄像头—写 DDR—读 DDR 测试通过。本轮没有为通过测试去改写侧或期望值。证据 `../tmp/v5_display_sim/20261020_131726/debug.log`（相对工程父目录）。
- 完整 PDS 构建检查返回码、错误、最终时序、位流及输入哈希。实际结果及证据位置见交付 `release.json`、`display_simulation.json`、`native_simulation.json`、`timing.rtr`。

没有上板、JTAG 下载、Flash 写入或物理 DDR/外部 IO/CDC 完整签核。上板效果仍需用户烧录这一份确定位流反馈。

## 交付

范围核对：对照原 V5 已交付构建的 224 个 source 文件，仅 `source/rtl/hdmi_ddr_ov5640_top.v` 与 `source/rtl/mpi7001_timing.v` 内容改变，算法、采集及 DDR 源码保持原样。这是文件身份核对，不是再次测试算法功能。证据 `JF/checks/v5_1_change_review/scope_check.json`；另有验证/交付脚本变化，最终 flow.tcl 和 FDC 均与原 V5 相同。

首轮 PDS（`JF/builds/v5_1_20261020_132247`）虽成功生成位流，但旧车道模块 `width_meta[84][11]` 至 `width_meta[85][11]` 有快角 hold −0.003ns，因此发布检查判为失败，没有打包。仅将布局种子从 4 改为 5 重新实现，RTL、时序要求及不相关算法不变；最终构建身份以发布记录为准。

第二轮 `JF/builds/v5_1_20261020_132909` 在另一对 `width_meta[15][3]` 至 `[16][3]` 寄存器出现快角 hold −0.002ns，同样拒绝发布。两轮均有正确频率和正 setup 余量，失败点是旧诊断逻辑的极短寄存器连接，不能据此解释原 V5 已通过时序却有现场花屏的原因。

查阅本机 `E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/doc/Pango_Design_Suite_User_Guide.pdf` 第 253 页（正文页码 252）：`fix_hold_violation_threshold` 及 `...for_clk_tree` 是“对 slack 小于该值的路径进行优化”的工具目标。第三轮保留种子 5，将目标由 350/200ps 改为 50/50ps，最大处理路径数设为 2000，集中修复实际负余量和不足 50ps 的路径；不改 FDC、不删除 200ps uncertainty、不改 setup/hold 验收条件。最终仍必须 `All Constraints Met` 才能交付。

第三轮 `JF/builds/v5_1_20261020_133538` 未通过最终时序，低修复目标没有解决问题，未发布。按用户进一步限定的范围撤销额外 PLL 拆分，FDC 恢复 V5，修复目标回到 V5 的 350/200ps，种子 6 重建。最终 RTL 只保留首 SOF 修正及输出黑边检查图案，不将无证据的 PLL 拆分作为正式修复。

定向通过记录：屏幕时序/检查图案三帧，独立 reader 两帧，以及 native 控制器 reader 两帧 460800 像素/3600 次 native 突发。native 证据为 `E:/zhoumian/FPGA/JF/checks/v5_1_native_20261020_132346`，涉及的时序/reader/控制器源文件未因时钟候选撤销而改变。早期显示仿真记录 `.../v5_1_display_20261020_132455` 含拆分 PLL 的比较用例，最终修改 PLL 测试后重跑，最终目录以 release.json 为准。第一次旧 reader 重跑期间测试文件发生编辑，`InputsUnchanged=false`，未用于发布。时序测试解除复位后等待一个仿真时间步再检查组合输出，避免夹具同事件竞争，不改变硬件期望。

目录：`E:/zhoumian/FPGA/JF/V5_1_MPI7001_800x480_DIAG`。

位流：`V5_1_MPI7001_DIAG_KEY8_cmos1.sbit`，操作说明 `README.md`。先看顶部色条，再观察中央默认原图与 KEY8 灰度模式是否错块，记录三者关系。

第四轮 `JF/builds/v5_1_20261020_134514` 保留单 PLL，但种子 6 最终有一条 fast hold −0.005ns，未发布。第五轮完全恢复原 V5 的种子 4 及 350/200ps 实现配置，源代码不变。最终显示仿真记录 `JF/checks/v5_1_display_20261020_134611`：PASS、InputsUnchanged=true。

## 最终构建结果

第五轮 `E:/zhoumian/FPGA/JF/builds/v5_1_20261020_135124` 完整构建 PASS，最终报告 `Design Summary : All Constraints Met.`，构建和两项仿真输入哈希稳定。显示域 slow setup +26.829ns、slow hold +0.358ns；这属于现有约束覆盖范围，不是完整外部 IO/CDC 签核。

最终 SBIT SHA256：`00CBF46936AAC6FC396D4E74E6980BA4E33DBBF6B87FDAC723614C2598B51A3A`。显示仿真为 `E:/zhoumian/FPGA/JF/checks/v5_1_display_20261020_134611`；native reader 仿真为 `E:/zhoumian/FPGA/JF/checks/v5_1_native_20261020_132346`。均 PASS、InputsUnchanged=true。未烧录，未上板验收，持续花屏根因仍待反馈。
