# M4-01 v0.1.2：FILE_TEST 播放与 Web 预览

实际部署：`/home/orangepi/fpga_gs_m401_v0_1_2_20261021`。SSH 用户 `orangepi`，其 HOME 为 `/home/orangepi`。本轮只证明 FILE_TEST 播放；没有 FPGA LIVE 帧率或识别准确率的新结论。详细实测见 `DELIVERY_v0.1.2.md`。

## 启动、查看、停止

Windows 终端建立 SSH 转发并登录（沿用已核对的主机别名）：

```powershell
ssh -t -p 22 -o HostKeyAlias=10.168.29.122 -o StrictHostKeyChecking=yes -o ExitOnForwardFailure=yes -L 18080:127.0.0.1:8080 orangepi@192.168.0.4
```

在该香橙派终端前台运行：

```bash
cd /home/orangepi/fpga_gs_m401_v0_1_2_20261021
.venv/bin/python main.py --mode FILE_TEST --video 1021_native_720p_30fps_12s.mp4 --scene scene.file_test.json --sample-fps 15 --preview-fps 15 --preview-width 640 --preview-quality 70 --loop --output runs/manual_v012 --web-port 8080
```

电脑打开 <http://127.0.0.1:18080/>。画面上方是连续道路录像和识别叠加；下方分别显示源文件 30fps、实际处理约15fps、浏览器实际收到的新帧fps、图龄和中文识别摘要。预览为640×360，识别/原图/保存快照仍为1280×720；UNKNOWN 保留为未知。JSON 默认折叠，文字约1秒更新。

停止：在运行 Python 的终端按 **Ctrl+C**，等待写入 `summary.json`；输入 `exit` 退出 SSH 并关闭转发。测试进程已经停止，没有后台服务或开机自启。

```bash
tail -n 5 runs/manual_v012/events.jsonl
cat runs/manual_v012/summary.json
```

`--duration 45` 可限时退出；`--sample-fps` 是 FILE_TEST 处理目标，`--preview-fps` 是 MJPEG 发布目标，均不代表硬件极限。不使用 `--benchmark` 验收播放流畅度。`--preview-width 1280 --preview-quality 82` 可恢复全分辨率 Web JPEG，但本次 Wi-Fi/SSH 条件下不能保证15fps。

## 样例来源与时间轴

原文件 `E:/zhoumian/FPGA/FPGA_GS/SC/1021.mp4` 报告平均39.628324fps、1280×720、3092帧，首段原生PTS间隔约25ms。新样例 `1021_native_720p_30fps_12s.mp4` 是前12秒的30fps CFR、360个不同原生帧，按解码时间戳丢帧选取，无复制、插帧。完整原生帧索引/时间戳见同名 `.provenance.json`。原文件与旧5fps样例保留。

本地重新生成时选用一个不存在的目标文件：

```powershell
cd E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/orangepi
.\.venv312\Scripts\python.exe make_native_sample.py E:/zhoumian/FPGA/FPGA_GS/SC/1021.mp4 runs/new_native_720p_30fps_12s.mp4 --seconds 12 --max-fps 30
```

生成器遇到非单调PTS或跨越超过一帧周期的缺口会报错，不用重复帧伪造帧率。播放时钟根据单调时间选择 CFR 样例的当前位置；处理落后就跳过旧源帧，没有待处理帧队列。循环从绝对经过时间推导，不把推理耗时累加进下一圈。

## 预览与统计

- `/stream.mjpg?t=...`：单个 MJPEG 连接；每次发送前只取最新发布帧。慢客户端在自己的HTTP线程内等待，写超时断开，不占用处理锁。
- 浏览器只保留当前JPEG和最新完整数据包，缓冲上限2MiB；成功解码且发布序号变化才计入新帧率。跨过的帧号不补算，重复JPEG不增加计数。断流/超时显示说明，自动重新连接；没有首帧时显示等待。
- `/latest.jpg`、`/raw.jpg`、`/status.json` 及其查询参数仍可用，动态响应禁止缓存。raw 为未经叠加的1280×720有损JPEG。
- 处理和预览fps使用近5秒窗口。图龄通过状态请求的往返窗口估计时钟偏移，再给出图龄上界估计，含网络/浏览器停留；设备没有同步时钟，不把它当单向传输延迟。
- 状态包括源fps、循环号、源位置、媒体时间偏差、推理/JPEG/整段处理耗时。日志仍保留每帧 observation 和重要事件；10MiB轮换一次，快照最多12对。未因猜测瓶颈删除日志或改为按需raw编码。

## 环境与范围

Orange Pi 5 / aarch64，Orange Pi 1.2.2 Jammy，Linux 6.1.99-rockchip-rk3588；Python3.10.12、已有OpenCV4.5.4、NumPy1.21.5，CPU执行。独立 `.venv` 使用 `python3 -m venv --without-pip --system-site-packages .venv`，没有新增板端依赖、sudo、模型下载或NPU转换。Windows 本地 `.venv312` 使用 requirements.txt 中已有依赖。

`vision.py`、`link.py`、协议快照、场景配置与v0.1.1哈希一致。未修改规则、UDP、FPGA、wlan0/eth0或系统服务。软件车道配置仍是明确标识的模拟场景假设，文件结果不绑定真实前摄KEY事件。识别边界与LIVE契约说明见历史 `releases/v0.1.1/README.md`（本地）或保留的v0.1.1远端目录。

## 本轮定向检查与再次部署

```bash
.venv/bin/python -m unittest -v test_playback test_web_preview
```

只检查播放时钟、查询路由、禁止缓存、首帧503、发布锁与MJPEG；不运行全套算法/模拟UDP测试。`verify_flow_browser.cjs` 通过现有Edge和Playwright在SSH转发地址运行30秒，证据见 `evidence/v0.1.2/`。浏览器注入503/断流/重复包只用于测试页面恢复及计数，实际流畅度采样阶段来自板端真实FILE_TEST。

再次部署脚本拒绝覆盖已存在目录，不传视频、不启动常驻进程：

```powershell
cd E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/orangepi
.\deploy.ps1 -ReleaseName fpga_gs_m401_v0_1_2_copy
scp -P 22 -o HostKeyAlias=10.168.29.122 -o StrictHostKeyChecking=yes runs/1021_native_720p_30fps_12s.mp4 runs/1021_native_720p_30fps_12s.provenance.json orangepi@192.168.0.4:fpga_gs_m401_v0_1_2_copy/
```

## 回退 v0.1.1

先 Ctrl+C 停止v0.1.2，在同一个SSH终端运行：

```bash
cd /home/orangepi/fpga_gs_m401_v0_1_1_20261021
.venv/bin/python main.py --mode FILE_TEST --video 1021_file_test_16s.mp4 --scene scene.file_test.json --sample-fps 5 --loop --output runs/rollback_v011 --web-port 8080
```

电脑重新加载首页即可。旧版本、旧样例及更早v0.1均未覆盖；无需恢复系统配置。
