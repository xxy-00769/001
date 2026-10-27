# M4-01 v0.1.2 交付报告

本轮已实际修改、独立部署并运行 FILE_TEST，完成播放及 Web 预览流畅度验证。只证明录像模式，未进行 FPGA LIVE 帧率/网口2联调，未重新评估识别准确率。

## 实际改动

- `make_native_sample.py`：读取原视频帧率和解码PTS，前12秒抽取360个不同原生帧，输出1280×720、30fps CFR样例及逐帧来源记录。没有重复帧或插帧；原文件、旧5fps样例保留。
- `playback.py`、`main.py`：FILE_TEST 默认目标15fps，按单调时钟选择当前源位置，落后跳过旧帧；绝对时间决定循环位置，不累计推理耗时。源帧率不足时不伪造帧。
- `main.py`、`preview.html`：MJPEG 单连接持续传最新帧，发送/等待都在HTTP线程，写超时2秒；浏览器有界解析并只解码最新完整包。状态/JSON约1Hz；HTTP查询路由、禁止缓存、等待首帧、失败自动恢复继续保留。
- 新帧计数依据成功解码且变化的发布序号；不按HTTP请求数、重复JPEG或跳过的序号计数。分别显示源fps、处理fps、预览新帧fps、图龄。图龄通过状态请求往返窗口约束时钟偏移，不宣称单向网络延迟。
- 实测证明预览传输受限后，才增加 `--preview-width` / `--preview-quality`。本次使用640×360、质量70；识别输入、raw接口和保存快照仍是1280×720。双图编码和逐帧日志保留，未无证据扩大CPU调优。
- `vision.py`、`link.py`、协议、场景配置与v0.1.1哈希一致。UNKNOWN不变；未修改FPGA、网络、系统包、驱动或自启设置。

## 部署及依赖

实际部署目录：`/home/orangepi/fpga_gs_m401_v0_1_2_20261021`。

回退目录：`/home/orangepi/fpga_gs_m401_v0_1_1_20261021`，原样保留；更早v0.1目录亦保留。SSH用户为orangepi，实际HOME=/home/orangepi。

Orange Pi5 / aarch64 / Jammy / 内核6.1.99-rockchip-rk3588；独立 `.venv` 复用Python3.10.12、OpenCV4.5.4、NumPy1.21.5，CPU执行，无NPU/模型转换、无新增板端依赖。新代码包 `m401_v0.1.2_code.tar.gz` 和 `.sha256` 位于本地orangepi及新远端目录；视频独立传输。

原视频报告平均39.628324fps，首段原生PTS约25ms；新样例 `1021_native_720p_30fps_12s.mp4` 为12秒/360帧/30fps、15,532,521字节。SHA256：

```text
原视频 bd46e9338842650c7637d3d7aae9ae5d9b5a9ef6737f87963fb74d1f6c4c0dc1
新样例 7250d00d3e5a17d609e3a963ebc45ed48242d4c20375a93881022f948faa41e3
```

本地样例及来源表位于 `runs/`，远端位于新版本根目录。生成命令、再次部署入口和参数说明见README。

## 实测结果与证据

使用现有可信SSH密钥/主机别名，通过电脑 `127.0.0.1:18080` 转发到板端 `127.0.0.1:8080`。电脑已有Edge的隔离headless实例实际打开首页，运行真实FILE_TEST动态录像。无安装浏览器依赖，无修改用户浏览器配置。

| 项目 | 实际结果 |
|---|---|
| 源样例 | 30.000fps、1280×720、12秒循环 |
| 浏览器连续测量 | 30.2025秒，449个新帧，**14.866fps** |
| 处理帧率 | 同期两份1Hz状态之间31.1315秒处理466帧，**14.969fps** |
| 全次板端运行 | 168.523秒处理2521帧，**14.959fps** |
| 推理耗时（全次运行） | 均值16.107ms，P95=20.607ms |
| 整段处理耗时（30个1Hz样本） | 中位27.88ms，P95=92.35ms；包含JPEG、日志、周期快照 |
| 图龄上界估计（30个样本） | 中位148ms，P95=719ms，最大765ms；含往返窗口余量 |
| 媒体位置偏差（30个样本） | 中位3.96ms，最大17.94ms，无随循环累计增长 |
| 循环记录 | 共14次；12、24、…、156.068、168秒，末圈回到时间轴 |
| 在途请求/排队 | 连续测量期间1个MJPEG连接；无重连、无重复帧计数；状态31次 |
| 停止 | 对本次记录并核对cwd的专属PID发SIGINT；正常写shutdown/summary，SSH前台退出0，8080释放 |

Wi-Fi/SSH存在偶发抖动，因此不宣称每个66.7ms间隔都均匀，也不把这一结果视为硬件性能上限。5fps旧样例、5fps处理目标、500ms网页轮询都是此前人为限制。

定位过程保留两份对比证据：全分辨率逐张请求约5.95新帧/秒；640预览逐张请求约10.42新帧/秒。板端本机JPEG响应约3ms，经转发单张约190–210ms；仅连接复用不足，最终使用MJPEG去掉逐张请求往返。达到目标后没有继续扩大调优。

已完成的定向检查：

1. 本机和板端 `python -m unittest -v test_playback test_web_preview`，7项通过：15fps位置选择、慢处理跳帧、跨圈调度、源fps上限、查询/缓存/空帧503、发布锁、MJPEG独立帧。
2. 实际首页在30秒内图像像素改变，跨多次循环，诊断JSON折叠；源/处理/新帧fps分别展示。
3. `/latest.jpg`、`/latest.jpg?t=arbitrary`、`/raw.jpg`、`/raw.jpg?t=raw`、`/status.json?t=status` 均200；JPEG实际解码通过（latest640×360、raw1280×720），动态响应no-store。
4. 浏览器仅在恢复/计数夹具阶段注入HTTP503、断流及相同帧包，验证等待、明确失败提示、自动恢复与重复帧零计数。这些夹具不用于流畅度或识别准确率结论。实际空服务器503另有板端HTTP单元检查。
5. 未重跑算法全套、模拟UDP或FPGA验证。

证据：`evidence/v0.1.2/browser_flow_report.json`、`02_continuous_file_test.png`、首帧/失败/恢复截图、`board_summary.json`、`board_events.jsonl`、`board_checks.txt`、样例生成和版本哈希记录。`verify_flow_browser.cjs` 为可复现的浏览器检查入口；处理fps按板端状态的单调时间间隔计算，避免1Hz采样错位冒充超额处理率。

## 完整启动、查看、停止、回退

Windows：

```powershell
ssh -t -p 22 -o HostKeyAlias=10.168.29.122 -o StrictHostKeyChecking=yes -o ExitOnForwardFailure=yes -L 18080:127.0.0.1:8080 orangepi@192.168.0.4
```

登录后的香橙派终端：

```bash
cd /home/orangepi/fpga_gs_m401_v0_1_2_20261021
.venv/bin/python main.py --mode FILE_TEST --video 1021_native_720p_30fps_12s.mp4 --scene scene.file_test.json --sample-fps 15 --preview-fps 15 --preview-width 640 --preview-quality 70 --loop --output runs/manual_v012 --web-port 8080
```

电脑打开 <http://127.0.0.1:18080/>，观察持续道路录像、识别叠加及中文摘要。正常应显示源30fps，处理/预览约15fps；停止 **Ctrl+C**，查看 `runs/manual_v012/summary.json`，退出SSH用 `exit`。本次验证进程已停止；不会占用用户下一次启动的8080。

回退（先停止新版本）：

```bash
cd /home/orangepi/fpga_gs_m401_v0_1_1_20261021
.venv/bin/python main.py --mode FILE_TEST --video 1021_file_test_16s.mp4 --scene scene.file_test.json --sample-fps 5 --loop --output runs/rollback_v011 --web-port 8080
```

电脑重新加载首页。无需删除新目录或恢复系统配置。

## 未完成项与指挥摘要

只交付FILE_TEST流畅度。网口2与FPGA LIVE仍未实物联调，不声称前摄LIVE帧率提高；识别误检/漏检限制不因本轮改变，缺少完整红绿灯/实虚线真实场景集，UNKNOWN保留。后台服务和开机自启未配置。

可复制回传：

```text
M4-01 v0.1.2已实际独立部署至/home/orangepi/fpga_gs_m401_v0_1_2_20261021，保留v0.1.1。原视频按PTS抽取原生帧生成12秒720p30fps样例，无重复/插帧。FILE_TEST按单调时间15fps调度、落后跳旧帧、循环不累计延迟；Web为最新帧MJPEG、640预览/JPEG70、状态1Hz。电脑经SSH转发实测30.20秒449个新帧=14.87fps，同期板端处理14.97fps；全次168.52秒14.96fps，14次循环不持续变慢。7项定向检查及网页等待/失败恢复/重复帧计数通过，SIGINT正常退出，8080已释放。算法/规则/UDP/FPGA/网络未改；仅FILE_TEST通过，FPGA LIVE未联调。完整启动和回退命令见orangepi/DELIVERY_v0.1.2.md。
```
