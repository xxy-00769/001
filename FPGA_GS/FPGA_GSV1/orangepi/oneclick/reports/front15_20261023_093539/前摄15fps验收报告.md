# M4-01 front15-r1：真实前摄15fps验收

2026-10-23，现场时间均为UTC+08:00。FPGA保持用户3.5.4，CAM0完整原图1280×720 RGB565小端，1440片/帧。**完整接收、处理及真实浏览器预览均达到本轮≥14fps目标。**

## 同一60秒实测

主窗口09:35:59.073—09:36:59.085，单调时间跨度60.001104秒，61次板端状态采样。浏览器提前启动，通过电脑127.0.0.1:18080的SSH转发接收真实MJPEG；按每个已解码图像携带的香橙派完整接收时刻筛选同一窗口，没有将重复JPEG或请求次数当新帧。

| 项目 | 实测 |
|---|---:|
| 周期HELLO.reason请求 | 15fps |
| 完整接收 | 896帧，14.9331fps |
| 实际处理 | 895帧，14.9164fps |
| SSH转发后浏览器成功解码新帧 | 867个不同sequence，14.4497fps |
| 浏览器按自身解码间隔测得fps | 14.4610fps |
| 同一服务socket drops增量 | 0（inode192449） |
| assembly_dropped增量 | 0 |
| 应用主动跳过完整帧增量 | 0 |
| NIC CRC / 硬件mmc_rx_crc_error增量 | 0 / 0 |
| 全机UDP RcvbufErrors / InErrors增量 | 0 / 0，仅作旁证 |
| send_errors / receive_errors / bad_packets增量 | 0 / 0 / 0 |
| 实际SO_RCVBUF | 8388608字节 |
| 浏览器视频连接最大在途数 | 1 |
| 浏览器重复帧计数 / 页面JS错误 | 0 / 0 |

收帧和处理计数首尾可能差一帧在途，本窗口主动跳帧增量确为0。浏览器只保留新图，867个已解码新帧不等于服务发布帧数；浏览器瞬时近5秒帧率会因调度/传输抖动低于窗口平均，截图不是固定15fps保证。最大相邻解码间隔392.1ms，无长时间冻结；首末约5秒的相对滞留差仅约+2.5ms，不显示持续累积的延迟。

接收、处理统计见`window.json`、`samples.jsonl`；浏览器见`browser_acceptance.json`、`browser_frames.json`；自动汇总见`acceptance_summary.json`。当前session/PID身份和硬件计数原文在上述文件中；没有跨重启/跨session累减计数。

## 帧间隔、耗时和图龄

以下按窗口内真实observation日志统计，没有重跑识别：

| 指标 | 平均 | P95 | 最大 |
|---|---:|---:|---:|
| 相邻完整帧到达间隔 | 67.00ms | 68.93ms | 89.96ms |
| 完整帧收齐到处理开始等待 | 2.60ms | 4.83ms | 16.90ms |
| 识别算法执行 | 13.23ms | 14.26ms | 29.08ms |
| 单帧处理总耗时 | 40.80ms | 50.23ms | 77.97ms |
| 叠加JPEG编码 | 3.74ms | 5.17ms | 7.14ms |
| 原图JPEG编码 | 8.01ms | 8.13ms | 10.86ms |
| 完整帧收齐到识别结果 | 29.81ms | 35.63ms | 46.78ms |

处理总耗时含RGB565转换、识别、叠加、JPEG和本帧触发的快照文件写入，不含随后observation日志写入；均保持既有处理行为。平均处理耗时低于约67ms输入间隔，未发现必须重写接收路径或调整算法的吞吐瓶颈。偶发单帧峰值未导致本窗口主动覆盖完整帧。

服务每秒采样的最大图龄为**110.8ms**，起点是香橙派收齐完整帧。它不是连续监控的绝对峰值，也不包含此前曝光、FPGA缓存与上传组帧时间。浏览器页面的图龄通过HTTP往返时序估计时钟偏移上界，含后续传输/解码/停留；同样不能称为摄像头到网页端到端时延。没有直接相减FPGA与主机时钟。

## 改动与不变项

- `main.py`增加`--front-fps`（0～30整数，默认15），传入Link并显示上传请求、处理目标及实际处理。`link.py`所有周期HELLO使用该值，删除写死5；识别/ACK/TTL/RESULT关联逻辑不变。
- 沿用已有接收线程及一个最新待处理帧槽，新增`skipped_complete_frames`记录待处理槽被新完整帧覆盖。它不影响socket、缺片或完整帧校验计数，不用残帧/旧图补足帧率。
- 记录真实分阶段耗时，显示近5秒完整接收fps；按既有冻结格式读取网口2TELEMETRY并保存，未增加或改变协议。窗口120条遥测，首尾mac_crc/mac_overrun及协议拒绝字段均无异常增长；这些网口2遥测不证明网口1右摄状态。
- `config.json`集中设置front_fps=15；启动参数、周期HELLO、控制台、状态和页面一致。网页继续640×360/JPEG70、15fps发布上限、单连接MJPEG；只统计成功解码的新sequence。
- 5fps/15fps切换入口先按旧参数安全停止，再修改统一配置并启动，保留接收缓冲修复。实际测试5fps生效后已恢复15fps，状态证据在`fallback_5fps_status.json`和`final_15fps_status.json`。
- `vision.py`、`vendor/protocol.py`和FPGA源码/位流未改，未降720p输入规格，未改网口1、HDMI、Wi-Fi、默认路由或DNS，无永久sysctl及开机自启。CPU执行，原Python/OpenCV/NumPy，无新增依赖或NPU转换。

## 现场条件与验证范围

用户明确确认右摄目前未运行；本轮只完成网口2真实前摄15fps与SSH预览，**双口并行条件未测**，未要求用户重做历史测试或重构建FPGA。

早一段60秒前摄同样达到约14.92fps且网络丢包为0，但浏览器验收脚本读取正在scp传输的window.json时遇到Windows临时文件锁。该段保留在`../front15_20261023_093319/`；修复脚本重试文件锁后形成上面的完整验收，无需改FPGA或香橙派接收架构。本机tabbit注册不可用，本轮沿用项目已有Edge/Playwright依赖实测页面，没有修复或重配浏览器环境。

针对性检查仅含：周期HELLO多次发送保持0/5/15/30配置值、单待处理槽覆盖计数、真实启动/停止与5→15切换，以及上述真实LIVE和浏览器窗口。未跑FILE_TEST、算法准确率或历史全套模拟通信。真实画面本轮并非道路验收场景，UNKNOWN仍保持未知，不宣称交通识别准确率通过。

## 部署、入口、观察与回退

实际目录`/home/orangepi/fpga_gs_m401_v0_1_2_20261021`；操作工具位于`operator_v1/`。本轮版本由`front15_release.json`标识M4-01-front15-r1，原v0.1.2归档保留。

电脑双击`E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/orangepi/oneclick/启动前摄预览.cmd`，网页应显示上传请求15、处理目标15、预览目标15，完整接收/处理约14.9fps、预览新帧接近15fps，前摄frame_id持续更新。显示的是实际新帧，帧号按CAM0采集身份可跳号，不要求连续+1。

停止用同目录`停止前摄服务.cmd`。关闭窗口/页面后远端继续运行。检查用`检查FPGA通信.cmd`，统计自动保存。

退到5fps用`切换前摄为5fps.cmd`，恢复15fps用`切换前摄为15fps.cmd`；这两者保留8MiB实际缓冲。完整旧源码与日志另存于`backup_before_front15_20261023_092549/`及远端`operator_v1/front15_backup_20261023/before.tgz`。

准确手动前台命令（先停止入口，避免重复进程；Ctrl+C停止）：

```bash
cd /home/orangepi/fpga_gs_m401_v0_1_2_20261021
.venv/bin/python main.py --mode LIVE_FRONT --bind 192.168.60.1 --peer 192.168.60.2 --port 50000 --peer-port 50000 --scene scene.example.json --front-fps 15 --preview-fps 15 --preview-width 640 --preview-quality 70 --output runs/live_dual_eth --web-port 8080
```

已有临时rmem_max=8MiB保持不变，重启后启动入口按需要求终端sudo认证，恢复方法沿用接收修复交付说明。后续永久配置、长时间稳定性、双口并行及按键闭环界面尚未完成。

可复制回指挥对话：

> M4 front15-r1已部署并完成真实LIVE 60秒：请求15fps，完整896帧/14.93fps，处理895帧/14.92fps，SSH转发Edge成功解码867个新帧/14.45fps；同socket drops、组帧丢弃、CRC及主动跳帧增量均0。完整帧间隔平均67.00ms/P95 68.93ms；处理平均40.80ms/P95 50.23ms；最大采样图龄110.8ms，从香橙派收齐完整帧起算，非摄像头端到端延迟。保留720p原图、640×360/JPEG70预览及8MiB缓冲，算法/协议/FPGA3.5.4未改。默认15fps，5fps回退与恢复15fps入口已实际验证；右摄未运行，双口并行未测。下一项可进入按键闭环界面。


## 发布末次核对及长期运行边界

`deployment_check.json`确认当前部署源码与发布清单一致，vision.py及vendor/protocol.py与修改前远端归档SHA256一致；周期HELLO及最新帧槽两项针对性检查通过，PowerShell脚本解析通过。版本清单为front15_release.json，旧status中的hardware_validation字段仍是历史固定文案“网口2尚未实物联调”，不代表当前实测状态；请以本报告、online及完整帧计数为准。

60秒验收结束后，恢复15fps的当前进程持续运行约6分钟时，累计assembly_dropped曾增至2；本次60秒零增量结论只适用于明确的验收窗口。末次09:46:27只读诊断采集4.037秒，收到61个完整帧、同socket drops增量0、CRC增量0、主动跳帧增量0，assembly_dropped首尾均为2。该短窗不能定位此前2次丢弃原因，也不等于长期零丢帧验收；没有为掩盖它重置计数或重启服务。原始数据见diagnose_20261023_094627_469.json。
