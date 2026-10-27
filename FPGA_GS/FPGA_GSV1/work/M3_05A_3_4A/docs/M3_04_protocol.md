# M3-04 3.3 遥测增量

保留GSV3版本1、48字节头和旧kind3心跳。新增FPGA→PC kind8，source0、profile1、width1280/height720、payload_len64。UDP零校验、Ethernet正常FCS；整帧154字节不含FCS。旧工具仍可消费旧心跳，建议配套3.3工具查看原因统计。

64字节为16个网络序uint32：mac_crc、mac_overrun、reject_format、reject_checksum、reject_session、reject_profile、sequence_errors、duplicate_packets、begin_wait_cycles、begin_requests、assembly_timeouts、assembly_aborts、ddr_beats、published、displayed_new、rx_packets。

计数按2^32回绕，加载复位；不复用KEY控制字段。约每0.5秒发送，优先级在控制/心跳之后、前摄视频片包之前，不中断在途包。MAC用跨域冻结payload/请求应答，显示数用Gray计数跨域；跨域存在有限观察延迟，快照不是线上时间戳。

每帧1440包、1843200像素字节。15/30fps像素单向载荷221.184/442.368Mb/s；每包额外48应用头+8UDP+20IPv4+14Ethernet+4FCS+8前导/SFD+12IFG=114字节，合计约240.8832/481.7664Mb/s。前摄5fps另方向像素73.728Mb/s、含开销约80.2944Mb/s。全双工分别计算，控制/心跳另计少量开销。

sendto间隔不是NIC线上突发测量；持续满线速或任意长DDR停顿不在已证明容量内。
