# M3-04 3.3 用户测试

用户自行加载新位流，不固化Flash。旧3.2包保留。接线沿用3.2：CAM0前、CAM1后，电脑扩展HDMI→板HDMI-IN为左，板HDMI-OUT→27B1，网线接网口1。输出应仍1080p60，输入/DDR/网口保持1280×720 RGB565。

有线网卡维持手动192.168.50.1/255.255.255.0，板192.168.50.2，UDP50000、1Gbps，直连无需网关/DNS。工具不改网络配置或安装依赖。已有Python/Pillow/tkinter/FFmpeg继续复用，端点在config/m3_endpoints.json。网口2不接入本轮功能。

## GUI观察

```powershell
cd E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1
python -X utf8 tools/m3/console.py --bind 192.168.50.1 --board 192.168.50.2 --video "E:/videos/road.mp4" --loop --ffmpeg "E:/ruanjianji/FlyingMouse/FlyingMouse Format/resources/ffmpeg/ffmpeg.exe" --right-fps 5 --front-fps 5 --auto allow --stats m33_gui_5.json
```

替换自己的动态视频路径；已有FFmpeg在PATH可省--ffmpeg。不带--video为动态图案，只作对照。工具置电脑主屏，左摄扩展桌面独立播放其他内容。GUI/headless不能同时占50000端口。

|步骤|正常效果|失败现象|
|---|---|---|
|加载3.3，查看显示器信息|1080p60稳定锁定，中文正常|输入不支持、锁定丢失、花屏|
|KEY5前→后→左→右→田字格|单路720p原像素居中，四格960×540、内容独立|水平错块、有效区黑块、错源|
|动态道路视频先5fps，右摄可见|不再持续只发布约一半，运动间隔较均匀|发送约5、发布仍约2.5，错误持续增加|
|保持右摄或田字格，无按键约70秒|预热5秒后同窗约60秒：发送/发布/显示新帧接近，前摄约5fps|只有请求值增大、板端显著掉队|
|改15fps重启工具，再测70秒|视频源足够时板端完整发布至少约14fps，显示新帧接近发布，运动明显更连续|实际发送不足，或发布持续丢近半帧|
|15通过后按需试30fps|如实比较实际发送/发布/显示值|不能把约28fps或静图重复写成达到30fps|
|切走右摄，再切回|隐藏仍发布，显示计数不增长；重选显示最新完整帧|隐藏停收、永久卡住、半帧露出|
|KEY6五种模式；前摄原尺寸查看/保存PNG|板上滤镜/提示保留，电脑始终CAM0干净彩色1280×720|电脑随板端错源/变灰、跨窗污染|
|KEY1～4、停车优先及模拟允许/拒绝/未知/告警|LED立即响应，唯一事件，旧结果不能覆盖新动作，过期未知|等网络才亮灯、旧反馈复活|
|暂停/恢复文件、停止/恢复发送、关工具重开|暂停停在同一时间点，恢复继续，新会话完整恢复|越播越慢、未完成帧发布、其他来源死锁|

暂停文件时工具仍发送新完整传输帧号的同一静图，发布/显示数可增加，**不代表运动帧率**。性能验收必须用动态源，右摄保持可见。单画面周围居中黑边正常，有效区黑块异常。

## 分别保存5→15→必要时30fps同窗统计

先KEY5保持右摄单画面/田字格，关闭GUI。每档运行70秒，排除前5秒，以最近约60秒遥测样本计算。5fps仍大量丢帧应先回传JSON；15通过后再试30。

```powershell
cd E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1
$roadVideo = "E:/videos/road.mp4"
$decoderExe = "E:/ruanjianji/FlyingMouse/FlyingMouse Format/resources/ffmpeg/ffmpeg.exe"
python -X utf8 tools/m3/console.py --bind 192.168.50.1 --board 192.168.50.2 --video $roadVideo --loop --ffmpeg $decoderExe --right-fps 5 --front-fps 5 --auto allow --warmup 5 --headless --seconds 70 --stats m33_board_5.json
python -X utf8 tools/m3/console.py --bind 192.168.50.1 --board 192.168.50.2 --video $roadVideo --loop --ffmpeg $decoderExe --right-fps 15 --front-fps 5 --auto allow --warmup 5 --headless --seconds 70 --stats m33_board_15.json
# 15通过后再执行：
python -X utf8 tools/m3/console.py --bind 192.168.50.1 --board 192.168.50.2 --video $roadVideo --loop --ffmpeg $decoderExe --right-fps 30 --front-fps 5 --auto allow --warmup 5 --headless --seconds 70 --stats m33_board_30.json
```

同一个window_seconds内比较window_pc_send_fps、window_board_publish_fps、window_display_new_fps、window_front_receive_fps。requested_right_fps只是请求；right_fps/front_fps是启动累计平均；board_publish_fps是短心跳量化值，不能混用。

window_deltas含：mac_crc（FCS/接收错误）、mac_overrun（MAC槽满）、reject_format（格式/长度/地址）、reject_checksum（IP/UDP校验）、reject_session（会话）、reject_profile（视频规格/边界）、sequence_errors（缺片/乱序不能继续）、duplicate_packets（忽略重复片）、assembly_timeouts/assembly_aborts（超时/新帧打断）、begin_requests/begin_wait_cycles（申请及100MHz等待周期）、ddr_beats（完成256bit写）、published（完整帧）、displayed_new（首次有效像素的不同发布）。正常申请也有握手开销，等待非零不等于无槽。

错误计数不应持续大量增长。未发布时DDR拍数仍可能增加，因为不完整帧的早期片已写入，但它不会被显示。电脑missing_packets/incomplete_frames专属前摄接收方向。

回传烧录版本、各档JSON、右摄是否可见/模式、视频规格、四阶段实际fps、错误增量和运动观感。板端15fps尚待实测，不因软件回环/仿真通过就进入网口2/M4。
