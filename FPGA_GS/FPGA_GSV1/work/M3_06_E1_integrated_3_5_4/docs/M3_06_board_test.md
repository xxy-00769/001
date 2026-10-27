# M3-06 3.5 最短双网口验收

本页是操作步骤，不表示已经上板。固件路径、时间、SHA和实际构建状态以交付报告/release.json为准。HDMI接线已由用户确认正常，本轮不要求重新设置分辨率。后摄绿点仍单列，不作为已修复项。

## 手工网络设置

- 网口1（两个RJ45中离HDMI较远者）：电脑原网卡 `192.168.50.1/24`，板 `192.168.50.2`。
- 网口2（靠HDMI-OUT）：香橙派有线网卡或电脑USB千兆网卡 `192.168.60.1/24`，板 `192.168.60.2`。
- 两条直连不设网关、不使用桥接/共享，不改现有Wi-Fi/SSH默认路由。UDP双方50000，普通1500 MTU。工具不更改网卡、路由、防火墙，也不安装依赖。
- 电脑只有一块有线网卡时，允许先逐口检查，再由真实香橙派加入组合验收。逐口切换需用户手工改变所接网卡的静态IPv4，不要求购买第二网卡。
- 两端需要千兆全双工。网口2固件拒绝百兆作为视频业务工作状态。PHY复位、等待、MDIO探测和协商需要时间，上电后先等链路稳定；不能以尚未协商完成时的零计数判断失败。

Windows在“网络连接→对应以太网→IPv4属性”手工填上述IP和掩码255.255.255.0，网关留空。不要修改无线网卡。检查本机没有重复地址；若防火墙拦截，由用户仅允许所用专用网卡的UDP50000。

香橙派先用 `ip -br link`、`ip -br address` 找到实际有线接口；再在系统网络设置中给该接口配置192.168.60.1/24、无网关。不要根据本页假定接口必然名为eth0；不要更改承载SSH的接口。这里不配置或部署识别算法。

## 电脑联调工具

从发布包 `source` 目录运行；已有Python、Pillow/tkinter以及原视频使用的FFmpeg继续复用。两个角色分别绑定各自地址，同机可同时运行。`--stats`不同角色默认分别保存，避免相互覆盖。工具留电脑主屏，HDMI扩展屏继续独立播放左摄。

Windows网口1测试图案（默认15fps）：

```powershell
python tools/m3/console.py --role right --right-fps 15
```

真实视频（替换为用户自己的文件；FFmpeg未在PATH时，沿用此前已能播放的实际路径）：

```powershell
python tools/m3/console.py --role right --right-fps 15 --video "E:/videos/right.mp4" --loop
```

网口2前摄/控制模拟：

```powershell
python tools/m3/console.py --role front-control --front-fps 5 --auto allow
```

不打开GUI的70秒记录：

```powershell
python tools/m3/console.py --role right --right-fps 15 --headless --seconds 70 --stats right_70s.json
python tools/m3/console.py --role front-control --front-fps 5 --auto allow --headless --seconds 70 --stats front_control_70s.json
```

香橙派如只运行同一联调工具：将发布包source拷贝到用户选定目录，在该目录运行：

```bash
python3 tools/m3/console.py --role front-control --bind 192.168.60.1 --board 192.168.60.2 --front-fps 5 --auto unknown --headless --seconds 70 --stats front_control_70s.json
```

上述是协议模拟，不是识别程序。香橙派现有开发任务应只读使用 `docs/M4_link_contract.md` 和未修改的 `tools/m3/protocol.py`，按自己的真实证据决定UNKNOWN/ALLOW/DENY；缺EVENT引用帧时不能冒用其他帧。

## 一次最短验收

1. 用户烧录唯一推荐位流，沿用原HDMI和摄像头接线，接两条网线并启动对应角色。KEY5到右摄：动态测试图或视频应连续更新；右摄统计同时区分请求15、电脑实际发送、板端完整发布和显示新帧率，不能只看请求值。持续CRC/溢出/组帧错误、掉帧增长或右摄冻结表示失败。
2. 网口2工具应显示前摄完整彩色图，完整接收率目标约5fps。勾选“前摄原尺寸1280×720”可看原尺寸。切换KEY5到其他视角，KEY6切换滤镜：本地显示按原功能变化，上传仍只应是CAM0干净彩色图。上传随滤镜变灰或来源改变表示失败。
3. 依次按KEY1/2/3，意图LED应立即左/右/直；网口2日志应出现对应唯一EVENT及RESULT_ACK，模拟允许显示允许。选择拒绝/未知/红灯/实线可观察对应反馈。长按不连发。KEY4停车时停车LED优先，按住KEY4再按KEY1～3，应提示停车优先且不新增被忽略动作EVENT。KEY5/6不上传驾驶动作。
4. 拔网口2：前摄预览停止，判定回UNKNOWN；网口1右摄应继续更新，板上KEY意图灯仍可本地响应。重新接上网口2、等协商/会话恢复，前摄和控制应恢复。不可因拔网口2导致HDMI/其他输入复位。
5. 拔网口1：右摄可以保留最后完整画面或按原健康状态提示失效；网口2前摄应继续更新、按键判定继续。重新接回后右摄恢复，不能清空网口2会话或让网口1判定覆盖网口2。

分别记录两角色统计JSON和烧录版本，回传用户实测的三种右摄率、前摄完整接收率、断一条另一条是否继续，以及后摄绿点是否仍存在。未进行这次板测前，不能宣布双口闭环已验收。
