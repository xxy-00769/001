# M4-01 v0.1 — 香橙派 CPU 识别与 GSV3 适配

本目录为本轮全部代码。实际部署目录 `/home/orangepi/fpga_gs_m401_20261021`；SSH 用户是 `orangepi`，其实际 HOME 为 `/home/orangepi`。未修改 FPGA、HDMI、共享协议、网卡配置、系统包或开机服务。网口2尚未实物联调。

## 已运行环境

- Orange Pi 5，aarch64，Orange Pi 1.2.2 Jammy，Linux 6.1.99-rockchip-rk3588，Python 3.10.12。
- 板端 `.venv` 用 `python3 -m venv --without-pip --system-site-packages .venv` 创建；复用已安装的 OpenCV 4.5.4、NumPy 1.21.5。没有新增板端 Python 包，也未用 sudo。已有 FFmpeg 4.4.2。
- 系统有 `librknnrt.so`，没有 rknn/rknnlite Python 包；全部处理在 CPU，OpenCV 限制为2线程；无模型下载、训练或 NPU 转换。
- Windows 本地 `.venv312`：Python 3.12.14，opencv-python-headless 4.10.0.84、NumPy 1.26.4，固定于 requirements.txt。最初 Python 3.9 venv 的 pip 因代理兼容失败，未用于验证。
- SSH 使用已有用户密钥。192.168.0.4 提供的 ED25519 公钥与 known_hosts 已信任的 10.168.29.122 完全一致，故使用 `HostKeyAlias=10.168.29.122`、`StrictHostKeyChecking=yes`；没有关闭主机验证，没有保存密码。

## 直接查看真实录像预览

Windows 终端一建立转发并登录：

```powershell
ssh -t -p 22 -o HostKeyAlias=10.168.29.122 -o StrictHostKeyChecking=yes -L 18080:127.0.0.1:8080 orangepi@192.168.0.4
```

在该香橙派终端前台运行：

```bash
cd /home/orangepi/fpga_gs_m401_20261021
.venv/bin/python main.py --mode FILE_TEST --video 1021_file_test_16s.mp4 --scene scene.file_test.json --loop --output runs/manual_file --web-port 8080
```

电脑打开 http://127.0.0.1:18080/ 。可看到 FILE_TEST 标识、真实录像、交通灯候选框、左右边界、未知/实线/虚线、K1～K4规则输出以及帧号/图龄/耗时。`/status.json` 为结构化状态，`/latest.jpg` 是叠加图，`/raw.jpg` 是未经叠加的原图 JPEG（有损预览）。Web 只监听香橙派127.0.0.1，500ms刷新，不逐帧scp。停止：在运行 Python 的终端 Ctrl+C；停止转发/退出登录：`exit`。没有后台服务或自启项。

样例是从用户授权的 `E:/zhoumian/FPGA/FPGA_GS/SC/1021.mp4` 前16秒按5fps抽取的80帧、1280×720 mp4v；只传输了这个约数MB的小样例。它是道路 FILE_TEST，绝不绑定真实前摄KEY。原录像不改动。`scene.file_test.json` 是该录像的手工相机/车道透视假设，醒目标为模拟场景配置；未选择交通灯归属，也不是车辆所在车道的实测值。

日志保存在 output 目录的 `events.jsonl`；单文件约10MB轮换并保留一份 previous；最多保留12对原图/叠加快照，默认每25个处理帧保存一次。网络输入同时保存 `raw_XXXXXXXX.rgb565`，每份1843200字节，是完整原始RGB565小端帧；JPEG只是便于预览。结束写 `summary.json`。查看：

```bash
tail -n 10 runs/manual_file/events.jsonl
cat runs/manual_file/summary.json
```

## 自检与模拟通信

```bash
cd /home/orangepi/fpga_gs_m401_20261021
.venv/bin/python -m unittest -v test_m401
.venv/bin/python simulate_peer.py runs/manual_simulation
cat runs/manual_simulation/report.json
```

测试覆盖红/绿/未知、停车、直行、左右实虚交换、无可靠边界、低置信度、错误会话、旧事件、精确帧等待、过期、丢片整帧丢弃及下一帧恢复、RESULT重试和ACK、独立收包心跳。simulate_peer 启动标为 SIMULATION 的独立进程，只用127.0.0.1：EVENT先于图像，传送两帧各1440片的RGB565测试图，验证红灯拒绝/绿灯允许、两次RESULT_ACK，以及断流退未知。合成图只证明图像候选逻辑、规则和通信，不证明真实识别准确率。

## LIVE_FRONT（待网口2硬件和网络就绪）

正式契约已读取并快照在 vendor/M4_link_contract.md。配置 endpoints.contract.json：香橙派192.168.60.1:50000 ↔ FPGA192.168.60.2:50000。实查 eth0 为DOWN且无IPv4；本次没有配置它，也没有改 wlan0。以下命令只有在用户/项目对话确认接线、烧录及网络配置完成后才可运行，现在未运行这组实物端点：

```bash
cd /home/orangepi/fpga_gs_m401_20261021
.venv/bin/python main.py --mode LIVE_FRONT --link-config endpoints.contract.json --scene scene.example.json --output runs/live_front --web-port 8080
```

CLI也支持明确的 `--bind` / `--peer` / `--port` / `--peer-port`；不写系统网络。HELLO请求前摄5fps，每250ms HELLO和心跳；不发送VIDEO_IN，不接管右摄。首轮先用 scene.example.json 的保守默认：未标定车道、未指定相关灯组，行驶请求通常未知。前摄实际接收率见 `/status.json` 的 link.front_receive_fps（进程运行期间的完整组帧平均率，包含空闲时间）；不是请求5fps就宣称收到5fps。

收包/ACK/重试线程独立于主线程推理。raw只保留一个最新完整帧槽；历史最多16份识别元数据且仅2秒有效。复用上游 Assembler 的固定缓冲、重复位图、32位向前比较及2秒丢帧恢复。每个RESULT只用完全相同frame_id的真实识别结果；缺图最多等800ms，并受原TTL减100ms本地余量限制，随后UNKNOWN；无邻近帧替换。新事件立即停止旧事件等待/重试，旧事件仅ACK不重复执行。

FPGA约30fps采集但5fps抽帧上传，事件绑定的latest_frame_id可能永远没上传，UNKNOWN是契约规定的正确行为。FPGA根据自己的事件时钟执行 `event_age < ttl`，主机原样使用不超过2000ms的事件TTL，200ms有限重试，不延长。主机无法从首次收包得知单向传输耗时；本地等待预算不表示事件剩余真实寿命，最终TTL仍由FPGA裁决。ACK按session/event/sequence匹配；ACK=0无细分原因，重复sequence可能首次已生效，不代表撤销第一次结果。图龄只使用主机本地收齐帧时刻，不是曝光年龄或单向延迟。

## 识别与规则的范围

交通灯：限定ROI内HSV连通域，面积、圆度、长宽比筛选，再要求包围发光圆的独立细长暗色灯壳；多个候选、箭头/灯组不清或无候选均未知。颜色与候选是从图像计算，不使用帧号、固定类别或全图颜色计数。`signal_actions` 必须由明确测试场景配置指定哪些动作关联该ROI内唯一灯体；默认空，不自动推断车道归属。该配置只描述测试假设，不模拟红/绿识别值。真实路口灯组自动归属尚未实现。

车道：手工相机ROI透视到320×240，白/黄局部对比掩膜，左右纵向峰值、分段中心拟合、残差及沿线占据率/间断长度判断。已确认相机几何时，连续覆盖>85%且无显著间断才判实线；覆盖22%～76%、至少3段且2个间断才判虚线；不够证据或几何未确认则未知。confidence是启发式门限分数，不是校准概率。曲线、阴影、护栏、路面文字、磨损、宽线/导流区、遮挡会造成误检或漏检，不能作为真实交通执法系统。

停车是驾驶意图允许，不作红灯告警；相关红灯下行驶意图拒绝并给reason1。绿灯且归属明确时，直行可允许，不要求变道；左右动作再检查对应边界，实线拒绝reason2、虚线允许、未知则未知。灯态/归属低置信度或不明确先返回未知，不凭任意红灯或未归属的实线强行告警。左/右按KEY比赛模拟动作解释，没有测量车辆实际转向/变道，也没有定义KEY5/6或新LED。

道路类型、车道数、斑马线、车辆/行人/障碍物、比赛专用所在车道选择按键、强制动作与告警交互尚未实现。只在香橙派当前输入预览画框/线，不回传标注整帧，不扩展FPGA协议，也不把前摄标注画到其他视角。

## 本地运行、再次部署与回退

Windows本地：

```powershell
cd E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/orangepi
.\.venv312\Scripts\python.exe -X utf8 main.py --mode FILE_TEST --video E:/zhoumian/FPGA/FPGA_GS/SC/1021.mp4 --scene scene.file_test.json --loop --output runs/local_manual
# 本地预览 http://127.0.0.1:8080/；Ctrl+C停止。
.\.venv312\Scripts\python.exe make_sample.py E:/zhoumian/FPGA/FPGA_GS/SC/1021.mp4 runs/new_sample.mp4 --seconds 16
```

部署脚本只创建新的独立目录，已存在则拒绝覆盖，不复制视频、不运行常驻进程、不安装系统包：

```powershell
cd E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/orangepi
.\deploy.ps1 -ReleaseName fpga_gs_m401_next
scp -o HostKeyAlias=10.168.29.122 -o StrictHostKeyChecking=yes runs/1021_file_test_16s.mp4 orangepi@192.168.0.4:fpga_gs_m401_next/
```

回退：Ctrl+C停止新版本后，进入保留的 `/home/orangepi/fpga_gs_m401_20261021`，按上面FILE_TEST命令启动。首个版本若不再使用，只需停止进程、退出SSH转发；没有系统级更改需要撤销。不默认删除目录、改软链接或改自启。
