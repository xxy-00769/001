# FPGA_GSV1 M3-06 3.5

本版完成双网口分流的RTL、定向验证及真实综合/布局布线/STA，尚未烧录、尚未板端验收。用户确认HDMI正常和3.3右摄15fps流畅；基线为3.3实际发布源码，3.4未交付WIP独立保留。本版不改HDMI、摄像头、滤镜，不追30fps、不开发识别。

- 网口1：右摄VIDEO_IN及自身会话/心跳，工具角色right，目标15fps。
- 网口2：CAM0干净原图上传及KEY/RESULT/ACK/心跳，工具角色front-control，上传先5fps；仍只有一个前摄网络读者。
- 1080p60、四路、滤镜、中文、KEY/LED及停车优先保留。两端独立端点/会话/PHY复位，实际帧率和断链恢复待上板。

工程入口：本source目录的`FPGA_GSV1_M3_06.pds`；命令构建为`./scripts/build_m36.ps1`。不要用根目录3.4 WIP的旧工程替代本发布源码。

唯一位流在本source上一级：`FPGA_GSV1_M3_06_3_5_DUAL_ETH_HDMI_1080P60.sbit`，SHA/时间/资源/时序见上一级`release.json`。保持时间最小余量0.028ns，未包含PCB偏斜，外部TX/电气未完整签核。

唯一对接契约：[M4_link_contract](docs/M4_link_contract.md)。[本轮修改](docs/M3_06_changes.md)、[手工网络设置、准确命令和最短测试](docs/M3_06_board_test.md)。协议48字节GSV3 v1、RGB565小端、每帧1440片×1280字节像素，与3.3逐字一致。

从本目录运行：

```powershell
python tools/m3/console.py --role right --right-fps 15
python tools/m3/console.py --role front-control --front-fps 5 --auto allow
```

两个命令使用不同网卡/IP：电脑原网卡192.168.50.1/24接网口1，香橙派或USB千兆网卡192.168.60.1/24接网口2，直连不设网关。工具不更改网络或安装依赖。真实视频在right命令后加`--video "实际视频文件绝对路径" --loop`。香橙派无GUI模拟命令见测试文档，不包含识别程序。

最短验收：右摄继续更新→网口2前摄原彩色约5fps→KEY判定及停车优先→分别断一条网线另一条继续→恢复。显示切换/滤镜不得改变前摄上传来源和颜色。只有一块电脑网卡时可分端口测试，再用真实香橙派组合联调。

后摄绿点仍为独立未解决反馈。本轮没有自动烧录、Flash固化、网络设置、软件安装、M4算法或30fps优化。
