# 3.5.2 最短板测（ARP捕获诊断候选，未宣称恢复）

1. 此版只修正诊断计数并增加实际ARP记录，未改变原发送电气设置，不预期凭此消除CRC故障。完整STA结果见交付报告；不是时序签核通过的功能修复版。若执行这一次有区分力的诊断，用户自行加载发布目录唯一NET2_ARP_CAPTURE_DIAG位流。沿用原接线与LIVE_FRONT；香橙派网线恢复FPGA网口2，电脑右摄仍网口1。保持原IP及业务端点，不安装依赖。
2. 若仍残留临时静态邻居，仅执行一次 `sudo ip neigh del 192.168.60.2 dev eth0`；提示不存在即可忽略。约5秒后 `ip neigh show 192.168.60.2 dev eth0` 应自动出现02:00:47:53:56:32，不能是INCOMPLETE/FAILED/PERMANENT。
3. Web应online=true，心跳、分片和完整CAM0彩色帧持续增加；前摄应为干净彩色原图。记录10秒实际接收fps，未测不承诺帧率。
4. 若仍失败，不重复移线或算法检查。在电脑PowerShell进入本版source，沿用此前采集3.5.1日志的COM号：

```powershell
& ./tools/m3/read_net2_diag.ps1 -Port COM7 -Seconds 5 -Output net2_diag_352.txt
```

COM7仅为示例。串口115200、8N1，输出N2 352，原22个状态字后追加18字（完整72字节MAC实际ARP输出，含前导码/SFD/填充/FCS）。回传net2_diag_352.txt即可；不必重新做网口1对照。若要手动解码：

```powershell
python -X utf8 ./tools/m3/decode_net2_diag.py net2_diag_352.txt
```

预期目的/目标MAC为00:00:a4:b5:5f:ef；源/发送者MAC为02:00:47:53:56:32；发送者IP192.168.60.2、目标IP192.168.60.1；opcode=2、padding=true、fcs_valid=true。

- 若记录缺失：生产MAC未形成可记录的完整72字节ARP，与PHY电气问题分开处理。
- 若记录字段/FCS错误：定位真实MAC/RAM/运行时内容；不改PHY相位。
- 若记录完整正确，主机仍CRC失败：问题在记录点后的序列化/IO/PHY/物理发送段。记录点在MAC GMII，不能声称串口证明引脚或线上字节正确。

5. 闭环恢复后，仅抽查一次网口1右摄15fps与1080p60显示/滤镜。KEY/RESULT下一步再联调，不扩大本次验收。

本次3.5.1实物对照已完成：同一香橙派/网线，网口2十帧全CRC错误；网口1十帧增加640个好帧字节，CRC零增量。不要重复该对照。

本候选撤回无充分物理依据的12mA增强驱动试改，六个网口2TX输出保持发布3.5.1的4mA/FAST。未改变PLL、边沿、PHY寄存器或协议。新增TX接收窗口STA若有负裕量，按失败报告，不作通过声明。
