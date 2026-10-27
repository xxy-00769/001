# E1采样入口修复（仅工具，2026-10-22）

双击 `tools/采样网口2实验.cmd`，按提示输入已有SSH/sudo密码。沿用config.json的主机、用户名、端口和StrictHostKeyChecking=yes。

流程：SSH创建用户家目录下fpga_gsv1_e1_tools → SCP上传原sample_net2.py → ssh -t执行sudo python3 ./fpga_gsv1_e1_tools/sample_net2.py --interface eth0 --seconds 10。不再内嵌Python源码。密码输入不采集、不保存；不更改网络配置或服务。

stdout即时写入报告；stderr即时显示并在阶段结束后单独追加，防止Connection closed插进JSON。密码提示无需换行即可显示。每阶段检查原生退出码；最终还检查唯一BEGIN/END标记、JSON及必要字段。任何执行失败、缺标记、JSON不全显示“采样未完成”，进程退出1；结果完整则退出0，硬件不通过仍可算采样完成。保留结束暂停。

实际Windows CMD入口已通过远端mkdir、SCP、SSH TTY、用户输入sudo密码、10秒采样和结果返回。原现场报告tools/reports/E1_sample_20261022_183718_701.txt原样保留：BEGIN/END均存在，SSH退出0，收到100个板端ARP请求、20个ARP回复，动态邻居REACHABLE，硬件CRC增量0，E1基础ARP收发通过。该报告包含最后一次日志修复前的stderr混入：Connection closed插入tx_deferred键中，不能作为严格JSON文件直接导入；不要改写原始证据。

最终stdout/stderr分离修复已用生产启动函数和校验代码定向检查：20KB JSON与stderr交错仍保存完整；完整结果+正常关闭提示接受；无结果标记拒绝；完整结果但原生退出7拒绝。见evidence/tool_fix_20261022/checks_console.txt，夹具明确标识FIXTURE_NOT_HARDWARE。最后的日志分离改动未再次要求用户进行板端采样，现场结论来自上述原始采样。

本轮不修改RTL、sample_net2.py采样行为、config.json、CMD入口或位流；未运行FPGA仿真/构建。位流SHA256仍为f6d7c5a46cd9508e146d18c5d67a44bc38f46bdc26cabab80252b95cc7e145a4。

E1通过只证明本板在官方结构最小工程下ARP基础收发及该10秒窗口CRC正常，不表示完整视频工程的网口2已恢复。此次不扩大到整机集成。