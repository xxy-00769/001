# FPGA_GSV1

2026-10-22 网口2现场不通自查：已交付 **M3-06 3.5.1 NET2被动诊断候选**，构建/布线/STA通过，**尚未确认硬件根因，未宣称真实收发或前摄闭环恢复**。基于发布3.5，3.4 WIP未用；没有修改PHY配置、ready门控、CRC、HDMI、摄像头、滤镜或协议。见[本轮报告](reports/M3_06_3_5_1_delivery.md)、[唯一候选及冻结源码](release/FPGA_GSV1_M3_06_3_5_1/README.md)、[一次板测与15秒串口采集](release/FPGA_GSV1_M3_06_3_5_1/source/docs/M3_06_3_5_1_net2_test.md)。请勿把下文旧3.5“待上板”状态当作现场通过。

当前交付（2026-10-21）：**M3-06 3.5双网口分流，构建/布局布线/真实STA已通过，待上板**。基于实际发布3.3；网口1右摄15fps目标，网口2前摄5fps及控制。HDMI接线问题已确认，修复任务撤销；HDMI、摄像头和滤镜未改。

[唯一新发布包](release/FPGA_GSV1_M3_06_3_5/README.md)、[完整交付报告](reports/M3_06_delivery.md)、[M4唯一通信契约](docs/M4_link_contract.md)、[准确命令与最短板测](docs/M3_06_board_test.md)。工程打开`release/FPGA_GSV1_M3_06_3_5/source/FPGA_GSV1_M3_06.pds`；根RTL仍有3.4 WIP，不作为本版工程入口。

STA setup+0.197ns、hold+0.028ns，DRM94、CLB56.17%、PLL5/5。网口2接收hold余量较小，外部TX/PCB电气未完整签核；双口实际帧率和断链恢复待用户验证。3.4 WIP隔离保留，后摄绿点仍独立未解决。未自动烧录/固化、未改网络或安装依赖，未追30fps或开发识别。

以下为此前各轮历史记录，状态冲突以本次3.5交付及用户最新反馈为准。

当前有效决定：用户确认HDMI正常，先前黑屏是线没接好，撤销下面M3-05/M3-05A修复任务。3.4失败WIP保留隔离；后续基于已上板3.3，15fps已流畅。进入[双任务分工与SSH开发安排](docs/M4_远程开发与分工.md)：[FPGA网口2分流](docs/prompts/M3_06_dual_ethernet.md)与[香橙派M4-01独立开发](docs/prompts/M4_01_orangepi.md)，用户人工分别转交。网口2尚未实施，香橙派可先离线推进，真实闭环待端口就绪；不再追30fps阻塞主线。后摄绿点尚未确认消失，保留独立事项。

用户最新纠偏：M3-05 3.4未交付，暂停其同时整改HDMI/摄像头时钟/IO的扩大方案。当前优先[M3-05A HDMI最小恢复](docs/prompts/M3_05A_hdmi_minimal_restore.md)：保存WIP，按发布基线撤回未经证实的输入重构，保留3.3已流畅15fps，优先恢复左摄；后摄绿点另行处理。只做修改直接关联的必要检查，30fps/网口2/M4继续暂停。

最新状态（2026-10-21，优先于下文历史状态）：3.3网口15fps用户确认流畅，截图发送14.37/发布14.27/显示14.31fps；HDMI左摄失效、后摄边缘绿点仍未确认恢复。M3-05 3.4已修改输入寄存、摄像头相关时钟交接及分阶段诊断，定向检查通过，但最终真实STA保持时间失败（慢角最坏−4.569ns），**没有发布推荐新位流，本轮未完成烧录交付**。输入±1ns预算仅工程假设，不能作为现场根因。详见[真实交付状态与失败证据](reports/M3_05_delivery.md)、[无位流源码证据包索引](reports/M3_05_wip_package.json)。保留旧包，暂停30fps优化、网口2/M4。

开发位置：`E:\zhoumian\FPGA\FPGA_GS\FPGA_GSV1`。

已完成基线：M3-04 3.3完成网口右摄吞吐定向修复、生产MAC到DDR/显示检查、综合/布线/STA并冻结打包；用户已上板确认15fps流畅。30fps未获实物验收，HDMI左摄与后摄回归按M3-05处理。

历史3.2上板反馈：PC发送约4.89fps、板端平均发布约2.58fps，丢弃270帧。该吞吐问题已由[M3-04网口右摄帧率优化](docs/prompts/M3_04_network_fps.md)推进至用户确认15fps流畅；保留历史[M3-03 HDMI修复](docs/prompts/M3_03_hdmi_compatibility_fix.md)记录。

历史任务：[M3-02普通1080p显示器、真实视频右摄与发送性能](docs/prompts/M3_02_hd_display_real_video.md)。使用普通1080p显示器；采集/网络仍720p。网口1暂共用电脑联调，M3收尾拆分为网口1接右摄视频源、网口2接香橙派承载前摄原图及按键/判定/心跳，分流闭环后进入M4。网口2及M4尚未实施。

## 已发布 M3-04 3.3 工程入口

位流：`release/FPGA_GSV1_M3_04_3_3/FPGA_GSV1_M3_04_3_3_NETWORK_FPS_HDMI_1080P60.sbit`；工程`FPGA_GSV1_M3_04.pds`。生成2026-10-21T15:50:56.828220+08:00。[交付](reports/M3_04_delivery.md)、[修改](docs/M3_04_changes.md)、[准确命令和用户验收](docs/M3_04_board_test.md)、[遥测](docs/M3_04_protocol.md)。5/15fps完整720p收包仿真通过，30fps组合检查通过，实际STA setup+0.482/hold+0.137ns，DRM89、CLB44.89%。未宣称板端达标。

## 历史 M3-03 3.2 工程入口

位流：`release/FPGA_GSV1_M3_03_3_2/FPGA_GSV1_M3_03_3_2_HDMI_1080P60.sbit`，工程`FPGA_GSV1_M3_03.pds`。生成2026-10-21T13:44:33.687702+08:00；完整SHA、资源/STA与证据见[3.2交付报告](reports/M3_03_delivery.md)、[修改记录](docs/M3_03_changes.md)、[逐步验收和准确命令](docs/M3_03_board_test.md)。

标准1920×1080p60输出；单画面720p原像素居中、四格960×540；保留全部滤镜/中文、四路采集、文件右摄/暂停循环、CAM0干净彩色原图上传及KEY/LED/停车优先。按真实关键路径增加增益/色彩/DRM读后流水；提示约2秒。PLL仍5/5，DRM81，CLB42.12%，最差setup+0.100ns、hold+0.088ns。未自动烧录，外部IO电气、板端时钟和27B1显示仍待实测。

```powershell
cd E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1
python -X utf8 scripts/check_m32.py --case format
python -X utf8 scripts/check_m32.py --case display
python -X utf8 scripts/check_m32.py --case processing
pwsh -File scripts/build_m32.ps1
```

## 历史 M3-02 3.1（27B1上板显示验收失败）


3.1位流：`release/FPGA_GSV1_M3_02_3_1/FPGA_GSV1_M3_02_3_1_HD_REAL_VIDEO.sbit`；完整处理链工程`FPGA_GSV1_M3_02.pds`。生成时间、SHA256及实际资源/STA见[3.1交付报告](reports/M3_02_delivery.md)与发布包release.json。源快照、工具及证据随包保留。

输出1920×1080/30Hz，单画面1280×720原像素居中、四格每路960×540直接取样；KEY5前→后→左→右→田字格，KEY6原有五模式，中文/驾驶反馈适配。CAM0独立三槽/网络读者，上传保留原始彩色；电脑工具支持真实文件、暂停/循环、测试图和原尺寸前摄预览。

网口1 RTL8211E/RGMII，PC192.168.50.1，板192.168.50.2，UDP50000；集中配置`config/m3_endpoints.json`。两次60秒双向软件回环请求右摄5/15fps，实得约4.88/13.31fps、前摄约5fps，均非板端实测；15及720p30未达。

```powershell
cd E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/release/FPGA_GSV1_M3_02_3_1/source
python -X utf8 scripts/check_m31.py --case display
python -X utf8 scripts/check_m31.py --case reader
python -X utf8 scripts/check_m31.py --case processing
python -X utf8 scripts/check_m31_host.py
pwsh -File scripts/build_m31.ps1
python -X utf8 tools/m3/console.py --bind 192.168.50.1 --board 192.168.50.2 --video "E:/videos/road.mp4" --loop --ffmpeg "E:/ruanjianji/FlyingMouse/FlyingMouse Format/resources/ffmpeg/ffmpeg.exe" --right-fps 5 --front-fps 5 --auto allow --stats m31_stats.json
```

视频路径需替换为自己的文件，Python3.9+/Pillow/tkinter及已有FFmpeg；不带`--video`为测试图。[本轮实现与验证边界](docs/M3_02_changes.md)、[手动网络配置/准确命令/逐步测试/60秒板端统计](docs/M3_02_board_test.md)、[协议增量](docs/M3_02_protocol.md)。用户自行烧录，工具不改网卡、不安装依赖、不固化Flash。回退3.0包`release/FPGA_GSV1_M3_01_3_0/`（原工程`FPGA_GSV1_M3_01.pds`）及已验收2.1包完整保留。

## 已验收 M2 基线（从发布包源码回退）

目标 PGL50H-6IFBG484 / 通用MES50HP，PDS2022.2-SP6.4。CAM0前、CAM1后、HDMI-IN左持续采集；输出MPI7001 800×480，内容区640×360。KEY5前→后→左→田字格，KEY6原图→灰度→3×3彩色均值→二值→Y/Cb/Cr三灰度栏。KEY1～4意图灯、停车优先、六键约2秒提示、已有显示增益保留，DDR原图不受显示处理影响。

```powershell
cd E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/release/FPGA_GSV1_M2_02_2_1/source
python -X utf8 scripts/check_m2.py --case full
python -X utf8 scripts/check_m2.py --case regression
python -X utf8 scripts/check_address_m2.py
pwsh -File scripts/build.ps1
```

[本轮交付与实际检查/时序/资源](reports/M2_02_delivery.md)；[电脑设置、接线和用户逐步验收](docs/M2_02_board_test.md)；[本轮修改与旁路边界](docs/M2_02_changes.md)。原 [M2架构与算法](docs/M2_01_architecture.md) 保留。

已验收基线：`release/FPGA_GSV1_M2_02_2_1/FPGA_GSV1_M2_02_2_1_RESTORE_VIDEO.sbit`，生成于2026-10-20 20:40:04 +08:00。工程 `FPGA_GSV1_M2_02.pds`，发布包含准确源码与证据。2.1完整处理版已获用户确认，2.1B仅保留历史诊断用途，无需继续上板。旧包和工程保留，工具不会自动烧录或固化Flash。

电脑 HDMI-OUT → 板 HDMI-IN，板 HDMI-OUT → MPI7001；Windows扩展屏，活动信号1280×720、60/59.94Hz、SDR/RGB8bit。三路实际画面及显示功能已获确认，外部IO延迟仍未完整签核。2.1实际FF8625、LUT9727、DRM43.5，CLMA1869/6450、CLMS1202/4250约29%；滤波两行各2 DRM/0存储FF，现有STA通过。

历史证据：[M1-02 1.1交付](reports/M1_02_delivery.md)，旧包 `release/FPGA_GSV1_M1_02_1_1/`；[M1-02用户反馈与进入M2评审](reports/commander_M1_02_review.md)。

## 阅读入口

当前指挥任务见页首M3-05。历史[M3-01网口双向视频与控制](docs/prompts/M3_01_network_video_control.md)说明当前单口联调实现。M2显示及CDC/帧管理修复作为已验收基线保留。历史[M2-02任务](docs/prompts/M2_02_restore_video.md)、[M2-01任务](docs/prompts/M2_01_hdmi_processing.md)保留，Flash固化延后。

协作入口：[开发指挥与反馈约定](docs/开发指挥与反馈约定.md)。当前指挥对话负责下发提示词与评审，另一个开发对话负责实现，用户转交执行结果并自行上板。首条执行提示词：[M1-01 双摄基础版](docs/prompts/M1_01_dual_camera.md)。

1. [FPGA优先开发方案V2](docs/FPGA优先开发方案V2.md)：当前固定输入映射，M1～M3 FPGA 基础开发、M4 香橙派联动、M5 后续全景；后续实施从这里开始。
2. [FPGA_GSV1开发准备与资料分析](docs/FPGA_GSV1开发准备与资料分析.md)：资料分析、接口细节、复用依据及带宽。旧架构和阶段顺序已由最新方案更新。
3. [当前对话整理与FPGA_GSV1开发交接](当前对话整理与FPGA_GSV1开发交接.md)：历史决定、已交付状态与协作边界；保留原文，架构冲突以最新用户要求为准。
4. [资料阅读索引](docs/preparation/资料阅读索引.md)：逐份文档用途、重复内容和压缩包处理记录。

## 后续主线

输入固定为：CAM0 前摄、延长排线后的 CAM1 后摄、HDMI-IN 左摄、网口输入右摄。FPGA 负责四路完整帧缓存、KEY5 多视角/田字格、KEY6 当前画面基础处理、中文与结果叠加和 HDMI-OUT。四路持续采集，显示处理链共享；前摄干净彩色图独立上传，不受显示模式影响。

香橙派5 / RK3588S 与 FPGA 联动完成道路理解、复杂识别与驾驶判断，通过网口接收 FPGA 前摄原图和按键事件并返回判定/告警/显示结果。前期用一个电脑工具验证网络图像和控制回路，后续复用到香橙派。

开发顺序：M1 双摄实景及统一框架 → M2 HDMI 左摄、四宫格结构与基础处理 → M3 网口右摄、前摄上传及控制闭环 → M4 香橙派真实识别。四宫格稳定后单独开发 M5 全景，不作为香橙派联调的前置条件。首份交付直接包含双摄实景，工程整理/彩条/单摄调通作为内部检查点。

旧工程和原厂资料按模块参考，保留原件与历史位流；本目录的1.0状态与旧V1～V5.2分别记录。用户自己烧录和反馈现场效果。
