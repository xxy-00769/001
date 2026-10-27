# M3-06 3.5 双网口分流

基线为实际发布的 `release/FPGA_GSV1_M3_04_3_3/source`。用户确认3.3右摄15fps流畅；HDMI问题为接线，M3-05/05A修复已撤销。3.4未交付WIP已独立存档，不作为本版源码来源。后摄绿点保留为独立未解决反馈。

## 实际修改

- `rtl/board/fpga_gsv1_top.v`：增加网口2引脚及独立实例；网口1仅右摄、网口2前摄上传及控制；把原CAM0网络读者迁往网口2，保持单个上传读者、原三槽与中止排空。反馈仅来自网口2。
- `rtl/network/m3_network.v`、`m3_net_core.v`：按角色裁剪右摄存储、包缓存、上传和控制；独立MAC/IP/session/心跳/计数与PHY队列复位。网口1RESULT不改反馈，网口2VIDEO_IN不写DDR。
- `rtl/network/m36_phy2.v`：网口2独立MDIO扫描RTL8211E、读改写并读回内部延时设置、千兆状态与停钟检测；复用原约84ms PHY复位后等待50ms配置，不依赖网口1锁相。
- `rtl/network/m36_rgmii_interface.v`：本端RXC经IOCLKBUF作IDES4采样、IOCLKDIV二分频，每字两字节经八字小缓冲顺序送本端125MHz MAC。PLL仍5/5，未借用另一PHY的采样时钟。
- `constraints/mes50hp.fdc`：按已核实手册固定网口2引脚，双沿输入延迟1.2～2.8ns、时钟不确定度0.2ns；PHY2数据/控制物理输入延时15。异步分组显式包括本端派生时钟，保持相关62.5/125MHz路径参与STA。
- `config/m3_endpoints.json`与生成脚本集中配置两端点；`tools/m3/console.py`增加right/front-control角色。front-control不创建右摄发送线程/进程；right不能发送判定。真实视频、暂停循环、原尺寸前摄和模拟判定沿用。
- 唯一对接规范为`docs/M4_link_contract.md`，`tools/m3/protocol.py`与3.3逐字一致。KEY.frame_id引用core接收本地事件时最近完整CAM0帧；5fps上传可能未上传该帧，缺证据应UNKNOWN。

57个已有RTL文件逐字不变，包含HDMI、摄像头、滤镜、DDR仲裁、CAM0所有权、MAC及右摄三槽模块。本轮没有重做其算法验证；核对记录见`reports/M3_06_baseline_diff.json`。

## 有证据后弃用的实现

直接全局时钟采网口2引脚出现真实保持时间违例；IOCLK驱动普通计数器不合法；IMDDR地址必须使用专用资源，普通地址方案不可布线。均未发布。最终使用已实际可布线的IDES4/IOCLKDIV方案。

小工程还证明：只将父时钟放入异步组会遗漏本端派生时钟到MAC的STA，因此最终约束加入`-include_generated_clocks`，没有把这些相关路径标作异步来隐藏违例。小工程已通过真实STA，整板结果以最终交付报告为准。

## 验证边界

已通过双端口完整1280×720组合检查，使用两个生产MAC、独立时钟、共享DDR仲裁、生产1080p读出路径。检查两完整右摄帧、两个完整1080p显示帧及1440片前摄完整上传，含DDR合法间隙、包积压、SOF相位、错误角色拒绝和网口2中途断链读者排空。

组合仿真以同延迟RAM模型加速，处理算法旁路但保留显示流水；最终生产位流保留完整滤镜及DRM滤波行存储。物理RGMII功能单独核对4096字节、首末拍及缓冲回绕；PHY/会话/TTL/旧结果拒绝另有定向检查。未重复软件回环、未重跑未改算法穷举。

尚未上板。两口同时工作时的右摄15fps、前摄5fps、实际PHY地址/延时配置、PCB偏斜、电气裕量和断链恢复均待实测；TX外部IO未完整签核，不将内部/接收STA写成全链路电气验收。
