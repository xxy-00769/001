# M4-01 v0.1 交付记录

日期：2026-10-21，Asia/Shanghai。交付范围为香橙派软件；实际新建/修改文件只位于 `E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/orangepi/`。未修改 RTL、约束、FPGA工程/位流、共享协议或已有相机/HDMI方案，也未联系其他对话。

## 实现与实际运行

- main.py：FILE_TEST / LIVE_FRONT / SIMULATION 三种明确模式、CPU推理、有界原图/叠加快照、RGB565原帧保存、JSONL日志轮换、本机Web预览、前台停止、最终统计。
- vision.py：真实图像的灯色候选与独立灯壳结构筛选；透视ROI内左右边界及连续性/实虚/未知；置信度及灯组/车道归属不明则未知。停车与直行不会被强制当成违规或变道。
- link.py：复用协议组完整CAM0帧、独立事件ACK/心跳/推理线程、精确session/event/frame关联、800ms以内有限等图、TTL内200ms重试、RESULT_ACK去重关联、断流未知、旧事件不覆盖新动作。
- 原始协议与正式契约的快照在vendor/；端点在endpoints.contract.json。新的正式契约在本轮执行期间出现，已按其最终读取内容对齐；未擅自给eth0配地址。
- README.md：完整启动、查看、测试、停止、再次部署、回退命令，以及算法/协议边界。deploy.ps1拒绝覆盖既有远程目录；部署不自动运行常驻进程或安装系统包。

实际部署：`/home/orangepi/fpga_gs_m401_20261021`。SSH登录用户名orangepi，实际HOME为/home/orangepi；端口22。CPU执行，OpenCV 4.5.4 / NumPy 1.21.5 / Python3.10.12，独立venv复用既有系统包；无新增板端包、无sudo、无NPU/模型下载。运行均为前台或带明确截止时间的前台命令；交付时已停止测试，无常驻服务。原视频未改动，只上传5,323,113字节的16秒/80帧FILE_TEST小样例。

## 测量与验证证据

文件 `evidence/board_file_summary.json`、`board_file_observations.jsonl`：香橙派真实录像样例80帧，不限速FILE_TEST；运行命令：

```bash
.venv/bin/python main.py --mode FILE_TEST --video 1021_file_test_16s.mp4 --scene scene.file_test.json --benchmark --max-frames 80 --output runs/file_delivery --web-port 8082
```

CPU纯识别平均14.113ms，P95 15.357ms；包含读取、推理、叠加、JPEG、快照/日志的活动期间吞吐28.279fps，80帧耗时2.829秒。此值是离线处理能力，既不是摄像头采集/FPGA上传帧率，也不是单向网络延迟。正常录像预览按约5fps抽样；Web按2Hz刷新。

该样例交通灯80/80 UNKNOWN。左边界18 SOLID / 4 DASHED / 58 UNKNOWN；右边界5 DASHED / 75 UNKNOWN。这些只是输出分布，没有逐帧人工真值，不能算准确率。它在傍晚、有遮挡/导流/磨损时常未知；可能把阴影/护栏/路面文字误当线，也可能漏检低亮度或弯曲车道线。灯体保守筛选可能漏掉远处小灯、横向灯体、箭头及复杂灯组。未建立真实灯组到本车道的自动归属；当前手工软件配置必须明确标为模拟场景假设。

文件 `evidence/tests_pc.txt`、`tests_board.txt`、`final_cli_and_tests.txt`：Windows及板端均6项针对性测试通过。包括规则正反例、低置信度、图像合成正负候选、实虚线合成夹具、错误会话、旧事件、TTL、丢片恢复、精确帧匹配、重试ACK、UDP心跳。合成样例不作为真实识别准确率证据。

文件 `evidence/board_simulation.json`：独立SIMULATION进程软件回环，真实发送每帧1440个GSV3分片；事件1绑定frame101红灯DENY reason1，事件2绑定frame102绿灯ALLOW reason0；两次RESULT_ACK接受，断流后未知。ACK量级低于1ms，实际精确数值见该报告；只代表板端软件回环，不能外推到FPGA物理链路。测试同时核对原始RGB565快照为1843200字节。

冻结检查曾有一次较快突发的回环夹具未收齐目标帧，程序在约803ms正确返回UNKNOWN，未借用其他帧；相关原始日志保留为 `evidence/incomplete_simulation.jsonl`。随后将回环夹具显式限速为每8片间隔2ms，只用来验证功能，不将其声明为5fps/80Mb/s吞吐验收。实际网口2丢包和持续吞吐仍待硬件实测；没有修改内核socket上限或系统网络参数。

文件 `evidence/preview_status.json`、`board_preview.jpg`：通过真实SSH本机端口转发18080→香橙派127.0.0.1:8080访问HTML/status/JPEG成功；图像已目视检查，标注仅在当前录像视角。没有开放公网监听、防火墙或远程桌面。

## 通过与未完成的边界

已通过：板端部署运行；真实道路FILE_TEST；CPU耗时测量；Web经SSH预览；本机UDP软件闭环；规则与组帧异常处理。RESULT无附加检测框，不发标注整帧。

尚未通过：网口2真实接线/PHY/UDP/丢包吞吐、真实CAM0完整帧、实物KEY→识别→板端文字告警、真实RESULT_ACK。正式端点已知，但eth0仍DOWN/无IPv4，本次未设置地址。网口2固件和比赛交互仍由用户人工对接。

尚缺真实验收素材：归属明确的红灯/绿灯/多灯组、左右实虚交换且有人工真值的连续画面、真实遮挡/阴影/失效例；本轮没有由这些样例验证的精度指标。手工软件车道/灯组配置不能代替比赛要求中的所在车道选择、强制动作按键或告警交互。KEY仅表达驾驶意图/比赛模拟动作，不宣称检测到真实车辆违章。

正式契约约30fps采集、5fps抽帧，KEY引用的帧可能完全没有上传。程序在TTL内等不到精确帧时返回UNKNOWN，这是当前契约下必须保留的限制；不能通过借用下一帧或延长TTL去提高表面命中率。无设备时钟同步，不提供单向延迟。

## 回传指挥对话

```text
【M4-01 v0.1 香橙派软件交付】
仅新增orangepi/，实部署/home/orangepi/fpga_gs_m401_20261021；CPU/Python3.10.12/OpenCV4.5.4/NumPy1.21.5，独立venv复用既有包，无sudo/网络改动/系统升级/自启。
已实现真实灯体候选及颜色、左右边界实虚未知、意图规则、CAM0完整组帧/原帧保存、独立ACK心跳、精确session/event/frame关联、有限等图与TTL重试、RESULT_ACK、headless本机Web/SSH预览。
PC与板端6项测试通过；板端SIMULATION完整GSV3回环红拒绝/绿允许及两次RESULT_ACK、断流未知通过；真实道路80帧FILE_TEST平均识别14.113ms/P95 15.357ms，离线总管线28.279fps。没有真实场景准确率声明。
已读取最终docs/M4_link_contract.md，配置192.168.60.1:50000↔192.168.60.2:50000；eth0仍未配置。网口2尚未实物联调，真实前摄/KEY/板端反馈未验收。30fps采集/5fps上传可能缺事件目标帧，必须UNKNOWN，不借帧。
使用README.md命令启动FILE_TEST并经SSH转发查看；原图/叠加快照、日志与证据在orangepi/evidence和板端runs/。缺真实红绿灯归属/标线真值素材；比赛所在车道选择/强制动作/告警交互未定义、未挪用KEY5/6或新LED。下一步用户确认网口2实物和网络后做LIVE闭环。
```
