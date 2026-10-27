# M4唯一通信契约：GSV3 v1 / M3-06双端口

冻结日期：2026-10-21（Asia/Shanghai）。维护方为本FPGA工程；香橙派读取本文件及`tools/m3/protocol.py`的冻结副本，不自行分叉协议。本文固定现有48字节头，不增加识别几何字段。M3-06硬件和组合性能尚待上板，不代表M3已验收。

## 端口与网络

| 项目 | 网口1 / right | 网口2 / front-control |
|---|---|---|
| 板上位置 | Ethernet1，两个RJ45中离HDMI较远者 | Ethernet2，靠HDMI-OUT的RJ45 |
| 板MAC | 02:00:47:53:56:31 | 02:00:47:53:56:32 |
| 板IPv4 | 192.168.50.2 | 192.168.60.2 |
| 对端IPv4 | 电脑192.168.50.1 | 香橙派或USB网卡192.168.60.1 |
| UDP双方端口 | 50000 | 50000 |
| 业务 | VIDEO_IN来源3、HELLO/WELCOME/HEARTBEAT及遥测 | FRONT_RAW来源0、EVENT/EVENT_ACK、RESULT/RESULT_ACK、会话/心跳及遥测 |
| 起始请求 | 右摄15fps；HELLO上传fps必须为0 | 前摄上传5fps；不发送VIDEO_IN |

配置源：`config/m3_endpoints.json`，独立MAC/IP/session/计数。/24直连，不填网关。以上是固件业务端点，不表示已替用户配置网卡。2026-10-21只读检查：电脑以太网已有192.168.50.1/24；未见192.168.60.0/24地址冲突；另一以太网为169.254地址。路由/防火墙仍需用户自行核实，工具不自动更改。只有一个网卡时可先分端口测试，再用真实香橙派组合联调，不要求购买第二网卡。

网口1的RESULT/EVENT_ACK不能修改反馈；网口2的VIDEO_IN不能写右摄DDR。一个端口HELLO重启、掉线或PHY复位，不清空另一个端口会话。只有网口2更新板上判定；断开网口2时反馈按TTL/会话超时回UNKNOWN，网口1右摄继续。

## 硬件及时钟依据

通用MES50HP / PGL50H-6IFBG484 / RTL8211E，非YT8614专用网口底板。依据硬件手册物理第23～24页表3-1/3-2及底板点位图2。网口2映射如下；方向相对FPGA，均LVCMOS33。

| 信号 | 网口1管脚 | 网口2管脚 |
|---|---|---|
| RXC / RX_CTL | F14 / F9 | M19 / B21 |
| RXD[3:0] | H13,G13,H11,H10 | F18,D22,D21,B22 |
| TXC / TX_CTL | G16 / B18 | C20 / F22 |
| TXD[3:0] | A18,C18,D17,F17 | F21,E22,E20,C22 |
| MDC / MDIO | A20 / C19，3.3原实现未使用 | G20 / G22，独立Clause22管理 |
| 低有效RESET | B20 | F19 |

网口1保留3.3原接收PLL及相位。网口2不增加PLL、不共用网口1RX时钟：自身RXC经IOCLKBUF供IDES4引脚采样，经专用IOCLKDIV二分频生成62.5MHz字时钟，每字两个GMII字节；八字小缓冲桥接到自身CLKBUFG的125MHz MAC域。Gray写指针同步后按固定顺序拆字节，相关时钟路径接受STA检查。PHY2数据/控制引脚使用物理PAP_IO_IN_DELAY=15补偿实测STA保持时间不足；这不是放宽输入时序约束。首次全局时钟直接采样和IMDDR普通地址方案已弃用。MDIO将RTL8211E配置为RGMII-ID（内部RX/TX各约2ns），发送数据/时钟同源ODDR，外部TX与PCB偏斜尚未完整签核、仍待实物验证。配置序列：扫描PHY地址1～31，核验ID1=001c、ID2高12位=c91；页寄存器31=7，扩展页30=00a4，读改写寄存器28，仅设置[13:11]=111，读回验证，最后31=0。延时字段依据Linux Realtek `rtl8211e_config_init`（以宏值为准；其邻近注释中RX/TX位次描述存在互换，双开不受影响），寄存器其余位保留。

硬件资料未给出可直接确认的PHYAD电阻值，不能把例程注释当实物地址；本实现运行时扫描并只接受RTL8211E芯片ID。地址0为广播，不用于探测/配置。启动复位保持至少原3.3的约84ms，释放后再等50ms；MDC为1MHz。配置读回正确后每约10ms读取reg17，要求[15:14]=10（千兆）、[13]=1（全双工）、[11]=1（协商完成）、[10]=1（实时链路）。同时要求本端时钟活动；连续约1.31ms未见时钟活动即关闭队列。10/100Mbps不作为本720p业务支持模式。停钟检测或链路状态下降时复位异步拉低，恢复时各时钟域同步释放；DDR读者按原中止排空释放，不能重置共享DDR。PHY停钟检测和MDIO轮询具有上述有限检测延迟，不能称为物理断线瞬间响应。

资料原件及文本/寄存器依据见`reports/M3_06_hardware`。以上为实现契约，PCB偏斜、电气眼图和现场链路仍待实测，不声称外部IO完整签核。

## GSV3 v1固定格式

以太网II / IPv4无分片、无IP选项 / UDP；固件验证来源IPv4和双方UDP端口，HELLO学习对端MAC。使用普通1500MTU，无巨帧要求。多字节头字段网络大端，像素RGB565小端。所有消息均带同一profile字段：format=1、width=1280、height=720。沿用`HEADER = !4sBBBBIIIHHIHHHHIIHBB`，恰为48字节。

| 偏移 | 字节 | 字段 |
|---|---:|---|
| 0 | 4 | ASCII GSV3 |
| 4,5,6,7 | 各1 | version=1、kind、source、format=1 |
| 8,12,16 | 各4 | session、frame_id、timestamp_ms |
| 20,22 | 各2 | width=1280、height=720 |
| 24 | 4 | payload_offset |
| 28,30,32,34 | 各2 | payload_size、fragment_index、fragment_count、flags |
| 36,40 | 各4 | event_id、sequence |
| 44 | 2 | ttl_ms |
| 46,47 | 各1 | code、reason |

类型：HELLO=1，WELCOME=2，HEARTBEAT=3，EVENT=4，EVENT_ACK=5，RESULT=6，RESULT_ACK=7，TELEMETRY=8，VIDEO_IN=16，FRONT_RAW=17。

每720p帧1843200字节，**1440片，每片像素1280字节**；UDP负载1328字节，不是历史草案1424字节。offset=index×1280，index=0～1439，count=1440。VIDEO_IN.source=3，FRONT_RAW.source=0。只发布完整帧；缺片/越界/乱序组帧失败后丢整帧，下一个合法新帧首片恢复，不把残帧当完整帧。

前摄主机组帧应使用`Assembler`：固定内存、重复位图、缺包整帧丢弃、2秒组帧超时、32bit帧号向前比较。来源/会话不同的包不得拼接。网络上传始终CAM0原始彩色图，不含显示亮度、滤镜或OSD。

## 会话、心跳及上传速率

每个端口由主机生成独立非零32bit随机session。主机每250ms发HELLO和HEARTBEAT；HELLO.reason是上传fps请求，网口1必须0，网口2先5（线格式仍支持0～30，固件夹到30；本轮不优化30）。0表示停前摄上传，不影响本地采集或另一端口。

无活动会话或当前会话相同才接受HELLO；活动会话期间不同session不能抢占，需旧会话2秒超时。新会话清本端event/判定状态；两个端口互不清理。有效同会话HEARTBEAT刷新存活；VIDEO_IN本身不代替心跳。FPGA约每500ms回HEARTBEAT并随后TELEMETRY。网口1右摄健康还要求3秒内有完整发布。

WELCOME确认会话。FRONT_RAW.timestamp为CAM0采集开帧的板上毫秒时标，不是主机时间；session只标网络发送会话，帧号是采集发布身份，不按上传重新编号。帧上传限速是请求值，不保证每个采集帧均上传。切换/掉线时在途DDR读返回必须排空；不得另增一个上传读者。

## KEY、停车和frame_id语义

KEY1左转、KEY2右转、KEY3直行、KEY4停车：本地消抖后LED即时更新，长按不连发，同时进入唯一网络事件。KEY5视角/KEY6滤镜保留本地行为，不上报驾驶动作。

停车按住或同时按下时优先。停车期间KEY1～3被忽略：本地提示保留实际键号及“停车优先”，不生成被忽略动作的EVENT；同拍多键沿用原本地优先级，不能当成多个独立有效动作。

EVENT.event_id为本端会话内递增身份；新有效动作使旧判定立即失效。EVENT.frame_id取**事件经本地按键mailbox到达DDR/core域时，CAM0所有权模块最近完整发布的latest_frame_id**，与显示视角、滤镜无关；不是主机最后收到的frame_id，也不是按键物理闭合那一刻的精确曝光。尚无前摄完整帧时可能为0。

CAM0持续采集约30fps，上传先5fps并会抽帧：主机可能在EVENT之前或之后才收齐所引用的帧，也可能永远没收到这一帧。主机不得把其他帧冒充事件帧。缺对应帧/证据时返回UNKNOWN或保持UNKNOWN；可缓存最近完整帧及等待短期限，但不得超过事件有效期。帧号32bit递增，主机不假设其连续上传。

EVENT携带code=实际KEY1～4，timestamp=事件core域锁存的板上ms，ttl头为2000。板端未收到EVENT_ACK时约200ms重发，同一event仅处理一次；超过事件年龄2000ms停止重试。EVENT_ACK至少同session和event_id；**现有RTL只按event_id确认EVENT_ACK，不校验其中frame_id**，主机仍应原样回填以便日志核对。

## 判定与ACK的实际规则

RESULT必须携带同session、当前event_id、EVENT.frame_id；sequence为本事件严格递增正整数。ttl_ms为1～2000，含义是**从板端事件时刻起的有效期**，不是从回包/主机发送时刻起另续一段。板端以自身ms判断event_age < ttl。主机不要用墙钟直接填板端时标。

code：UNKNOWN=0 / ALLOW=1 / DENY=2。reason：0普通判定、1模拟红灯告警、2模拟实线告警；仅允许0～2。reason=1/2优先显示对应告警；reason=0显示code。M4尚未提供几何结果格式，不能把附加payload塞入现有RESULT。

同时满足事件/会话/帧身份、sequence大于已接受值、TTL有效、code/reason合法、且同拍无新KEY事件，才更新反馈。旧回包不覆盖新动作。停车优先在KEY本地先执行，网络回包不反向驱动意图LED。

RESULT_ACK.kind=7，event/sequence回显请求，code=1接受或0拒绝，reason固定0（无细分拒绝原因）。现有ACK.frame_id来自板端当前event_frame，拒绝旧包时不保证等于请求frame_id；主机以(session,event,sequence)关联。重复相同sequence可能ACK=0，因为第一次已生效；不能把后续拒绝当作撤销第一次结果。主机可每200ms重发直到ACK或自身事件有效期耗尽；新动作应停止旧事件重试。反馈到事件TTL或本端会话超时回UNKNOWN。

## 遥测与联调边界

TELEMETRY负载64字节，`!16I`：mac_crc、mac_overrun、reject_format、reject_checksum、reject_session、reject_profile、sequence_errors、duplicate_packets、begin_wait_cycles、begin_requests、assembly_timeouts、assembly_aborts、ddr_beats、published、displayed_new、rx_packets。网口1报告右摄计数；网口2无右摄，相关字段为0；各端口MAC及拒绝计数独立。HEARTBEAT中flags=1，frame=右摄累计发布、offset=丢帧、sequence=bad_packets，网口2这些视频计数为0。前摄实际接收率由主机完整组帧计数测量。

电脑工具角色为`--role right`或`--role front-control`，按对应bind/board地址运行；准确命令随M3-06交付。香橙派识别程序只复用协议/契约，本任务不实现识别或替它建立SSH连接。最终板测要分列请求fps、实际发送、板端发布、显示新帧及前摄完整接收率，仿真不能代替实物结果。
