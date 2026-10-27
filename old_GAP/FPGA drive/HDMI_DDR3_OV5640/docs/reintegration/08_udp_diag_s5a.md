# S5a：诊断应用层与另一台电脑测试包

日期：2026-10-19。**本轮只完成 S5 的独立应用层部分，实体网口集成未完成。没有新可下载位流，没有视频上传。**

## 1. 需求、范围及实际结果

用户授权开始 S5，并要求本机没有网口时，说明如何在另一台电脑接收画面。
按此前约定，本阶段先完成小包双向通信，不越过小包验收直接做 S6 视频。

- 用户现场反馈：当前 FPGA HDMI 彩色视频顺畅。记为 V1 用户观察，非代理实测帧率、
  全像素、全边缘或长稳验收；本轮未独立读取板内位流身份。
- 实际完成：诊断控制 RTL、电脑客户端/模拟端、定向 RTL 与电脑回环测试、
  独立 PDS 编译/综合、可复制的工具 ZIP 与另一台电脑操作说明。
- 尚未完成：MAC/ARP/IPv4/UDP完整包适配、RGMII/PHY、顶层连接、LED物理映射、
  PNR/最终时序、位流、实体联网及视频收发。
- 不改变现有摄像头/DDR/HDMI，不向原工程清单加文件，不修改 FDC/IP/PLL。

## 2. 当前状态与保留

实际 Git 根：`E:/FPGA drive/HDMI_DDR3_OV5640`。
开始时分支 `main...origin/main`；HEAD 仍为
`6f68d09149f3fcf3927174887f80cea9225fae50`。
原有 README、四份生产 RTL 脏改动、未跟踪文档/工具及仓库外归档均保留。
未清理、未提交、未暂存、未重新备份旧工程。

本轮核对以下哈希与已交付 V1 记录相同：

| 保留文件 | SHA256 |
| --- | --- |
| `source/rtl/hdmi_ddr_ov5640_top.v` | `8D226F7501DBB0147AE9AC3F7FD01B755ED7C87B407C0BBC5D3CC94E25DE5878` |
| `source/rtl/img_proc.v` | `B77637F60F0B9F297692A236173125D76F9B561FB4743CE963DB914C0F19C833` |
| `source/rtl/wr_cmd_trans.v` | `2B99C581904A5C61FAA6EA8BF06065482A724A72C01CB4EF56FE86E53443F659` |
| `source/rtl/rd_buf.v` | `E2E4D26D2C84405B62A17C749CA00138BC438975A14992F5A920B99D0CCB8635` |

独立综合的 `inputs_before.json` / `inputs_after.json` 还覆盖主 PDS、flow、FDC，
以及本轮 RTL 与综合入口；均未变化。

## 3. 新功能及边界

新增 `source/rtl/net_diag/mes50hp_diag.v`，不在当前主顶层实例化：

- 一次接收一个已完整验证的 32 字节载荷；ready/valid 背压。
- CRC32、字段合法性、非零会话、递增序号。
- HELLO建立会话，PING返回状态，LED命令限定 1..5000ms 租期。
- 重复/旧序号不执行、不续租；会话竞争返回 BUSY。
- 默认 5000ms 无新有效命令使会话过期；断链/复位清除会话和 LED 请求。
- 单槽待发应答，输出在背压下保持；断链/复位允许取消。
- 接受/拒绝计数仅为模块端口，尚未连到板上可读统计。

协议只用于隔离网络诊断，不是驾驶控制，不包含视频，不具备认证/加密。
CRC是应用载荷校验，不代替网络底层完整包校验。

物理接入前，适配器必须先验证地址/端口、长度、IP/UDP校验策略、
最终以太网FCS、PHY错误，并处理部分包/超时/溢出和CDC。
不能将厂商 `udp_rec_data_valid` 直接当作完整包提交信号。
应用时钟及毫秒tick必须在RX时钟停转时仍能工作，否则不能保证租期退出。

完整协议、信号契约和覆盖范围见 `tools/s5_diag/README.md`。

## 4. 实际检查与证据

### 4.1 电脑与 RTL

命令：`tools/s5_diag/run.ps1`。

最终证据：

`E:/FPGA drive/tmp/s5_diag/20261019_183755_841_90d54889/`

- `result.json`：PASS，输入哈希未变化。
- `host_tests.log`：9项软件测试通过；包含实际操作系统UDP套接字和独立客户端子进程，
  HELLO/LED/3次PING共5次请求5次应答、0超时，但对端是软件，不是FPGA。
- `simulation.log`：ModelSim RTL，`S5_RESULT cases=281 errors=0`。
- `vectors/`：Python `struct/zlib` 生成的独立金标准。
- `commands.json`、`inputs_before.json`、`inputs_after.json`：实际工具调用与输入身份。

281项是定向检查数，包含256种单bit损坏，不是281种独立硬件场景。
覆盖租期边界、重复/旧序号、外国会话、坏CRC/字段、输出背压、同时出入队、
断链、复位重入、会话过期和禁止序号绕回。
RTL测试把会话期限参数缩短至50个毫秒tick，生产默认仍5000ms。
RTL没有实例化网络MAC/PHY，长度错误目前只在电脑解析器测试，未来适配器仍须验证。

保留的开发失败记录：

| 独立目录（同 `tmp/s5_diag/` 下） | 实际失败与修正 |
| --- | --- |
| `20261019_183607_882_54b73903` | 主机CRC固定预期常量手写错误；修正测试常量，非RTL失败 |
| `20261019_183636_530_b9ef96d0` | 向量脚本漏导入 `asdict`；修复脚本，RTL未运行 |
| `20261019_183659_801_2f57de4f` | ModelSim不接受先引用后声明的 `expiring`；移动声明 |
| `20261019_183726_448_31e8aecd` | 测试预期错误地认为未消耗tick的LED已过期；保留租期预期，不修改RTL绕过 |

### 4.2 PDS独立编译/综合

命令：

```powershell
.\tools\s5_diag\synthesize.ps1 -SimulationResult E:\FPGA drive\tmp\s5_diag\20261019_183755_841_90d54889\result.json
```

证据：

`E:/FPGA drive/tmp/s5_diag_synthesis/20261019_184124_096_471f888a/`

- PDS 2022.2-SP6.1，进程退出0。
- `result.json`：Compile=true、Synthesis=true、输入/复制RTL未变化。
- `compile/mes50hp_diag_comp.adf`、`synthesize/mes50hp_diag_syn.adf` 与综合网表存在。
- 顶层是**独立应用模块 `mes50hp_diag`**，不是整个视频工程编译。
- 没有 device_map/PNR/report_timing/gen_bit_stream，也没有下载/固化。
- 有工具许可证将于15天后失效提示、无IO约束提示、常量探测loop提示及常量/悬空位优化提示，
  不是零警告综合。未以未经约束的综合时序估计声称125MHz、RGMII或整机时序通过；
  综合后功能等价/门级仿真也未执行。

### 4.3 原版网口例程只读核查

命令：`tools/s5_diag/inspect_vendor.ps1`。

证据：

`E:/FPGA drive/tmp/s5_vendor_inspection/20261019_184422_491_c3cfa6fc/inspection.json`

原RAR：
`D:/BaiduNetdiskDownload/盘古50K开发板/2_Demo/11_ethernet_test.rar`

读取前后SHA256：
`2D2935BBF2840D56BA8422B1C9EE79B8B0582E08691135ED045EC890E29B7ED7`。
选择8份约束/源文件/IP配置输出为独立文本证据；未导入主工程。

实际观察：

- 原顶层有RGMII及PHY复位，没有MDIO/MDC管理口。
- 原示范是每次20字节固定字符串，不是图片。
- 例程ETH1约束写LVCMOS33、独立RX相位PLL；它们是例程设置，不是本机实测电气依据。
- `udp_rx.v` 在REC_DATA状态流出载荷；`mac_rx.v`之后才进入REC_FCS并检查CRC，
  现有应用端口没有提供“已验证完整UDP包”提交事件。

### 4.4 工具包

命令：`tools/s5_diag/package.ps1`。

交付：

`E:/FPGA drive/tmp/s5_diag_package/20261019_184124_074_b27c6b14/MES50HP_S5_tools.zip`

SHA256：
`18A2F59CC591D5CC4E2A65EE03EA68067CB46FD1AAD63F7F91DB4E532E029C9C`

ZIP中有客户端/模拟端 `link.py`、Windows启动器、中文操作说明、文件清单。
已向独立目录解压并逐文件核对哈希；没有把模拟器称为硬件链路。

## 5. 另一台电脑怎么用

现在即可：将ZIP传至另一台电脑，在解压目录依中文README运行软件回环；
只需Python3.10+，无第三方包。开发电脑无需网口，仍可承担USB/JTAG下载。

**当前不能收FPGA画面**：V1不发UDP，本轮没有新联网位流，也没有图像播放器。
未来实体链路版本交付后：板载已确认的ETH1用网线直连另一台电脑有线网口，
原HDMI/摄像头保持不变；预留板端 `192.168.50.11`、电脑 `192.168.50.105/24`、
UDP8000，最终以实体发布配置为准。README含有线网卡设置、限定防火墙规则、
诊断命令、日志和抓包反馈方法。不要求关闭全局防火墙或改Wi-Fi。

图像显示须在S5实体小包通过后，再开发S6测试图、分片重组、真实彩色视频。
此处没有提前冻结图像网络协议或声称任何帧率/带宽。

## 6. 精确的阻塞与下一步

目前缺少本机ETH1的PHY/底板版本对应、IO电源和strap/延时依据。
S1中相应实物栏仍待确认；本轮实际源码/约束核查未补齐它们。
**这只阻止新增PHY引脚/电压/时延设置及联网发布，不阻止独立应用RTL、软件或适配器逻辑开发。**

用户下一份有效输入可为：底板版本号、ETH1/PHY附近清晰近照，
以及与该版本相符的网口电源/strap原理图（已有资料若能对应也可，不要求重复全板拍照）。
照片能确认器件/版本，不单独证明电压和内部延时；电气信息仍须匹配资料或现场核验。
不需要补齐DDR/全IO签核才能继续做独立模块。

下一最小开发单元：基于完整包接收验证/提交适配器做原始以太网帧定向仿真，
再在上述网口依据充分后接入主顶层与对应约束，生成真正的S5实体测试位流。
本轮未完成这个单元，不能标记S5通过或自动进入S6。

## 7. 改动文件

新增：

- `source/rtl/net_diag/mes50hp_diag.v`
- `host/mes50hp_link/link.py`、`run_windows.cmd`、`README.md`
- `tools/s5_diag/diag_tb.sv`、`test_link.py`、`run.ps1`
- `tools/s5_diag/synthesize.tcl`、`synthesize.ps1`
- `tools/s5_diag/package.ps1`、`inspect_vendor.ps1`、`README.md`
- 本报告

更新：`docs/development/project_context.md`，记录V1用户反馈及S5a边界。

没有改动生产视频RTL/DDR修复、原README、主工程PDS/flow/FDC/IP、旧归档或旧位流。
本轮无需用户重新下载任何文件到FPGA。
