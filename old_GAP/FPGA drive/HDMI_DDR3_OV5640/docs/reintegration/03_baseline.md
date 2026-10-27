# S1 基线登记、硬件身份与恢复快照

日期：2026-10-19。范围：**仅 S1 的只读核查、备份、接口与验收规格**。

结论：已建立含工作副本、Git、脏改动、未跟踪/忽略内容和相关仓库外资料的文件级快照，并完成独立恢复抽查。**这不是基线工程重建、仿真、时序或上板通过；实物身份核对尚未完成。**没有修改 RTL、FDC、IP、PDS、构建配置，没有运行综合、布局布线、位流、下载或固化，也没有进入 S2 或修复历史 DDR 问题。

## 1. 本轮入口与重新登记的状态

| 项目 | S1 实际检查结果 |
| --- | --- |
| 工作入口 | `E:/FPGA drive` |
| 实际 Git/PDS 工程 | `E:/FPGA drive/HDMI_DDR3_OV5640` |
| 顶层 | `E:/FPGA drive/HDMI_DDR3_OV5640/source/rtl/hdmi_ddr_ov5640_top.v` |
| 适用约束 | 重新检查 `E:/AGENTS.md`、`E:/workspace/AGENTS.md`、入口及入口递归树，没有发现适用 AGENTS.md；没有把附件中的指令作为本轮操作授权 |
| 已读 S0 输出 | 本目录 `00_project_audit.md`、`function_matrix.csv`、`01_target_architecture.md`、`02_execution_plan.md`，作为历史审查而非当前状态证明 |
| 重新读取 HEAD | `6f68d09149f3fcf3927174887f80cea9225fae50` |
| 分支 | `main...origin/main`；未 fetch，不证明实时远端状态 |
| S1 开始时脏改动 | README 已有 5 行新增，保留；无已暂存差异 |
| S1 开始时未跟踪 | S0 四份报告及此前 17 个 reports/tools 文件，清单见快照 `metadata/git_before_untracked.txt` |
| 忽略项 | 生成目录、IP/旧构建产物、日志、impl 工程及锁文件等纳入复制范围，不以 Git 跟踪状态过滤 |
| 仓库外归档 | 入口下 `_archive`、`tmp`、`_diag_frames`、`log` 等均在备份范围，不迁移、不清理 |
| 本轮仓库新增 | 仅本文件及 `07_video_interface.md`；不改写 S0 四份文件 |

Git 读操作使用 `--no-optional-locks` / `GIT_OPTIONAL_LOCKS=0`，没有 stage、commit、clean、reset。复制前后索引 SHA256 均为：

`FF5432348221D65D6F7743903BC6E624BEDE492C65B81CC65C0B93AF430B35FF`

当前 Git 状态、refs、配置、跟踪/未跟踪/忽略清单、二进制形式工作区/暂存区 diff 已单独落盘，不沿用 A 结束时的状态。收尾结果见快照 `metadata/final_checks.json` 和 `metadata/git_final_status.txt`。

## 2. 硬件证据索引

以下页码均为 **PDF 物理页号，从 1 开始**，不是页脚数字。硬件手册页脚通常比物理页少 1。

| 编号 | 实际资料路径 | 已核查范围与边界 |
| --- | --- | --- |
| H1 | `D:/BaiduNetdiskDownload/盘古50K开发板/3_Hardware/MES50HP开发板硬件使用手册_1V1.pdf` | 38 页文本提取；重点核对物理 p1、5、7-11、20、22-23、35-37；渲染并查看 p1、10、20、23、36、37 |
| H2 | `D:/BaiduNetdiskDownload/盘古50K开发板/1_Demo_document/实验例程说明篇/10_OV5640双目摄像头实验例程v1.pdf` | 6 页文本；p1 模组/接口、p2-3 格式、p5-6 接法警告及二选一；查看 p5 图示。厂商照片不是本机实物照片 |
| H3 | `D:/BaiduNetdiskDownload/盘古50K开发板/1_Demo_document/实验例程说明篇/11_以太网传输实验例程说明v1.pdf` | p1 PHY/例程用途；不是当前工程已接通网络的证据 |
| H4 | `D:/BaiduNetdiskDownload/盘古50K开发板/3_Hardware/核心板连接座/50K_Base_Board.sch`、同目录 `.pcb` | 文件存在并已备份；未用 CAD 完成网络逐线/板版本匹配核验，不能当作完整匹配原理图已签核 |
| H5 | `D:/BaiduNetdiskDownload/盘古50K开发板/4_IC_datasheet` | 整目录备份，含 PHY 数据手册；未声称全部器件手册已逐页电气签核 |
| H6 | `D:/BaiduNetdiskDownload/盘古50K开发板/2_Demo/10_HDMI_DDR3_OV5640_test.rar`、`11_ethernet_test.rar` | 原始压缩包只读保留/备份，没有导入或升级 IP |
| H7 | `D:/WeiXin/xwechat_files/wxid_3prr1p2aefu622_c4ae/msg/file/2026-10/比赛开发文档_ADAS.md` | 用户整理资料已备份；不是官方原文全部合规性或现场硬件身份的证明 |

文本、源 PDF 哈希和图片证据在快照 `evidence/reference_text.json`、`evidence/manual_p*.png`、`evidence/camera_p5.png`。Poppler 对硬件手册报告 Symbol 字体替换警告；引用表格与重点页已结合图片查看，未据提取文字推断接线方向。

## 3. 硬件身份表

**工程配置、资料记载、实物确认三列不能互相替代。当前没有本机实物照片或本轮现场确认，所有实物栏均待确认。**

| 项目 | 工程配置证据 | 资料记载 | 实物确认 | 冲突/限制及仅受阻的操作 |
| --- | --- | --- | --- | --- |
| 核心板型号/版本 | PDS/flow 选择 PGL50H，未记录可对应实物的核心板 PCB revision/序列号 | H1 p7 MES50HP；文件名 1V1，p1 封面 V1.0、2024-7-19，是文档版本而非 PCB 版本 | 待核心板正反面、PCB 版本/标签、序列号照片 | 不能以手册文件名认定实物版本；阻止版本相关的引脚、电源和器件替换判断 |
| 底板型号/版本 | 工程无已确认底板 revision | H1 p21-37 扩展底板；H4 文件名不能代替版本链 | 待底板正反面、连接座和修订丝印 | 完整匹配原理图未确认；不据其他例程补引脚 |
| FPGA 型号/封装 | 主 PDS、flow、4 个 IDF：Logos / PGL50H / -6 / FBG484 | H1 p8：PGL50H-6IFBG484，工业级 | 待芯片完整丝印照片 | 工程与资料在系列/封装/速度上对应，尚非实物确认；阻止器件/封装/引脚改动 |
| DDR 颗粒与组织 | `source/rtl/DDR3_50H/DDR3_50H.idf`：MT41K256M16xx-15E、DQ32、row15/col10/bank3，输入 50、期望速率字段 800 | H1 p7 写 Micron；p10 明列 MT41K256M16TW-107:P / XCCC256M16EP-EKNAY / QN3B256M16H-16A，要求以实物为准；两颗各 4Gbit、合计 32bit，400MHz/800MT/s 为资料规格 | 待两颗各自丝印，不能只拍一颗 | IP 料号字符串与列举料号不同；不等同于已证实不兼容，也不等同于可互换。阻止 DDR 时序/IP/电气改动及实物参数签核，不阻止软件用例准备 |
| DDR 电源/引脚 | FDC 保留现有 IO 属性，含 HSTL15_I 等；本轮不改 | H1 p11：Bank3、1.5V SSTL，VTT/VREF 跟随；p11 起引脚表 | 待匹配图纸及必要的合格现场测量 | 属性命名差异须结合 IP/原语/实物核验；不能按文字相似性改约束或宣称电气通过 |
| PHY/网口 | 主顶层/主构建没有接入 PHY 收发端口、MDIO/RGMII 图像链路 | H1 p5 RTL8211E、双网口；p22 泛写 RTL8211，p23 为 ETH1/ETH2 表；H3 p1 RTL8211E | 待网口编号、PHY 完整丝印/版次、strap/复位、IO 电源及 RGMII 延时资料 | “支持 2.5/3.3V”不是本板实测电压；阻止 PHY 引脚/电压/时延配置与联网验收。没有默认旧网口例程可收发图像 |
| 双目模组/传感器 | 两套 reg_config/cmos_8_16bit 存在，CMOS1 被选为单路；寄存器及格式按 OV5640 例程。顶层残留 OV5647 注释不是身份依据 | H2 p1 Double_OV5640 为另配模组，不证明用户实物板载集成；p5 正文误写 ov5647 顶层，而截图为 ov5640 | 待模组正反面、版本、两颗传感器身份/购买规格、连接方式 | 不以注释认定 OV5647，也不以文件名认定实际模组。阻止传感器特有时序/电气变更；保留 CMOS1 文档基线 |
| 40 针接线与 IO | 根 FDC 例如 cmos1_data[7] 位于 AB13，同时写 VCCIO3.3 / LVCMOS12 | H1 p35 正文和 H2 p1 写 J8；H1 p36 图3-12座号却为 J16，表3-12列 pin3=AB13、pin2=5V0。H1 p35 明确 IO 不可直接接 5V | 待本板座号、pin1、排线两端方向/错位检查、电平与供电连通关系 | 座号、IO 属性均有待核对点；带 5V 电源脚不意味着 IO 耐受 5V。禁止按本表现场换线/上电 |
| 外部供电/核心供电 | RTL/FDC 不能证明适配器额定值、极性或接线 | H1 p20：核心 VCCIN=5V，经板间座供电；p37：底板外部输入 +12V，再转 +5V 给核心，是不同层级 | 待原配适配器铭牌、插口/极性、实际接线和板版本 | 不把核心 5V 与底板 12V 混用；本轮没有输出任何换电源指令。阻止未核对的供电/接线动作 |
| 时钟源 | sys_clk 约束 20ns；PLL 请求值及 FDC/旧报告见第6节 | H1 p8-10：50MHz、125MHz、27MHz 资源与系统晶振引脚表 | 待晶振/板版本、现场 PCLK 与显示时钟测量 | 约束不是示波器测量；阻止频率/采样相位已达标结论，不阻止只读计算 |

现场补证建议：在不换线、不改供电的前提下，提供核心板/底板/模组正反面、FPGA/两颗 DDR/PHY 清晰丝印、原配适配器铭牌及现有接线全景；照片需能关联到同一套板。现场电气测量应由具备条件的人员依据匹配图纸安排，本轮没有执行或授权。

## 4. 可恢复快照

### 4.1 位置、容量与范围

独立快照根：

`D:/MES50HP_Snapshots/S1_20261019T082916Z_d8742ddd`

新建唯一目录，不覆盖既有备份，位于全部源目录之外；已检查不会复制自身。D: 与源工程 E: 为不同卷/路径，但**未证明是不同物理磁盘**，不是离线灾备。复制起止为 2026-10-19 08:31:41Z 至 08:34:25Z；终端本地时间为 UTC+08:00，已同时记录 UTC，不套用会话声明的纽约偏移。

| 范围标签 | 原路径/内容 | 文件数 | 已核对 |
| --- | --- | ---: | ---: |
| workspace_entry | 整个 `E:/FPGA drive`，不只 Git 跟踪文件；含 `.git`、脏 README、全部归档、证据和忽略产物 | 7,428 | 7,419 |
| board_hardware | H1/H4 所在完整 `3_Hardware` | 11 | 11 |
| board_datasheets | 完整 `4_IC_datasheet` | 21 | 21 |
| vendor_camera_demo | H6 摄像头 RAR | 1 | 1 |
| vendor_ethernet_demo | H6 以太网 RAR | 1 | 1 |
| camera_demo_document | H2 | 1 | 1 |
| ethernet_demo_document | H3 | 1 | 1 |
| user_requirements | H7 | 1 | 1 |
| 合计 | 初始复制范围，不含后来新增 S1 文档补充包 | **7,465** | **7,456** |

枚举数据量 3,109,941,563 字节；复制前可用 19,389,521,920 字节；最低需求按数据量 120% + 1GiB 为 4,805,671,700 字节，容量检查通过。1357 个目录有独立清单，枚举错误 0。

复制以文件为单位，源前哈希/副本哈希/源后哈希及大小、时间核对；不是卷级原子快照。随后再次读取全部 7,456 个可读源文件，内容变化 0。未读取文件不伪造 SHA256，而在清单记 null 和错误。

### 4.2 清单与遗漏

所有路径以下均相对快照根：

| 证据路径 | 内容 |
| --- | --- |
| `metadata/preflight.json` | 新位置、源范围、容量、索引哈希、未跟随链接声明 |
| `metadata/manifest.jsonl` | 每文件原路径、scope 相对路径、副本路径、大小、UTC 修改时间、三次 SHA256、状态及错误阶段 |
| `metadata/directories.json` | 目录及其原路径/相对路径/时间，包括空目录 |
| `metadata/omissions_and_changes.json` | 9 个未成功读取文件；没有掩盖为复制成功 |
| `metadata/excluded_links.json` | 1 个未跟随的 junction 及目标记录 |
| `metadata/copy_summary.json` | 复制结果、每范围计数、索引复制前后相同 |
| `metadata/git_before_*.txt`、`git_after_copy_*.txt` | 新采集的 Git 状态、HEAD、refs、配置、index/worktree diff 及文件清单 |
| `metadata/source_recheck.jsonl` | 7,456 个源文件在复制后再次与初始清单核对 |
| `metadata/restore_manifest.jsonl`、`restore_git_checks.json`、`restore_summary.json` | 独立恢复记录、逐文件哈希和 Git 对象检查 |
| `metadata/final_checks.json`、`evidence/timing_readonly.json` | 收尾保护/新增清单检查及本轮只读时钟证据 |
| `metadata/s1_supplement_manifest.jsonl` | 最终两份 S1 文档另存副本/哈希；不覆盖初始工作副本快照 |

9 个占用文件全部在原工程根下：

```text
impl.pds.lock
log/cfg.log
log/configuration.log
log/js.log
log/jtagserver.log
pds.log
run.log
stderr.log
stdout.log
```

合计 388,518 字节未读到内容；它们是锁/工具日志，影响完整原样工具会话和日志恢复，**不能声称“所有文件完整备份”**。源码、4 个 IDF 及生成源、FDC/PDS/flow、主机/测试/模型、已有位流和已枚举仓库外归档未出现在失败清单；其副本已按清单核对。没有绕过锁或结束其他任务。

唯一未跟随链接为 `E:/FPGA drive/tmp/reintegration_audit_20261019/node_modules`，指向 Codex bundled runtime。保留链接目标元数据，未复制目标依赖库，恢复时不自动重建链接。递归枚举对 reparse point 一律停止，不穿越 junction；本轮没有清理原目录。

### 4.3 独立恢复抽查

恢复目录：

`C:/Users/19511/AppData/Local/Temp/MES50HP_S1_restore_2de6d2fc176a4767bdc3fda6fb86d5b4`

只从快照 `payload` 复制到新目录，不覆盖原工程。共恢复 **1,209 文件 / 241,790,183 字节，哈希失败 0**。包括主工程全部成功备份文件和完整 `.git`，另含外部硬件/数据手册/原始例程/用户细则，以及 v11 现场验收记录、位流/掩码、选定源文件、v12 timing_audit、历史 DDR README 等样本。精确逐文件选择在 `restore_manifest.jsonl`，不声称恢复了整个 3.1GB 快照。

在恢复出的 Git 中实际执行：

```text
git --no-optional-locks ... rev-parse HEAD
git --no-optional-locks ... fsck --full --no-dangling
git --no-optional-locks ... show HEAD:source/rtl/hdmi_ddr_ov5640_top.v
```

三条退出码均 0；恢复 HEAD 与原 HEAD 相同。`fsck` 检查对象库，不证明 RTL 可综合，也不替代工作副本哈希。没有 checkout/reset，脏 README 直接由文件副本恢复；可按 `payload/workspace_entry/HDMI_DDR3_OV5640` 映射恢复工程，而不是用 HEAD 代替全部现状。

恢复操作只做复制、哈希、Git 读取，未运行恢复目录中的 build、脚本、工具钩子或位流。

### 4.4 恢复能力边界

| 能力 | 结论 |
| --- | --- |
| 当前源码/配置/脏改动及已枚举归档内容恢复 | 文件内容副本存在；主工程可读部分已实际恢复，其他范围逐文件复制哈希 + 代表样本恢复 |
| 全文件逐字节原状恢复 | **未满足**：9 个锁定文件未读；一个 runtime junction 目标未备份；没有 ACL/ADS/整机卷镜像级保证 |
| 同一瞬间的整个工程状态 | **未证明**：文件级复制，复制前后 Git/索引与可读文件复核一致，不是原子一致性机制 |
| 完整工具环境复现 | **未满足**：没有备份 PDS 安装、许可证、仿真库注册、驱动、系统/GUI 会话、全部 Python/Node 包或香橙派环境 |
| 当前工程重新构建/时序/上板 | **未执行，未知**；恢复 Git 对象和文件不能提升验证等级 |

若未来需要全文件/工具环境镜像，应另开明确范围任务；锁定文件只能在持有者正常释放后另存补充记录，不覆盖这次失败事实。本轮到此为止，不为追求完整率结束进程。

## 5. 单路彩色规格入口

详见 [S1 单路彩色接口草案](E:/FPGA drive/HDMI_DDR3_OV5640/docs/reintegration/07_video_interface.md)。它分别记录当前信号与目标契约；干净彩色候选点、帧号/坏帧接口、参考存储字节序都未据此实现。网络字节序仍待冻结，本轮没有扩展图像协议。

当前 DDR 写入口是经过候选着色、斑马线叠加和 ADAS HUD 的 `proc_rgb/proc_de/proc_vs`，不是未叠加主图。当前分工为 FPGA 采集/缓存/整理/可选特征/传输，PC 后迁移香橙派负责最终感知、规则与显示。旧“真实感知 -> FPGA 本地规则 -> FPGA 最终显示”链只作诊断证据保留，不继续扩大正式产品架构。

## 6. PLL/IP、FDC 与旧时序只读对应

以下文件均保留原样，完整路径、哈希和摘录见快照 `evidence/timing_readonly.json`。

| 项目 | 当前文件所写内容 | 旧报告/对应性 | 本轮判断 |
| --- | --- | --- | --- |
| sys_clk | 根 FDC 第723行 20ns；PLL IDF 输入 50MHz | 根 report_timing 报告 sys_clk=20ns | 文本量级相符；不是实测频率 |
| 像素 PLL | `source/rtl/pll/pll.idf` basicPage 请求 CLKOUT0=37.125MHz；顶层 clkout0->pix_clk | 根 FDC 第751行 27/20，即67.5MHz；旧报告 pix_clk=14.8148ns/67.5MHz | 请求值/约束/旧报告不同，当前有效网表/实测未知；没有将任一文字当作唯一真值 |
| 生成 PLL | `source/rtl/pll/pll.v` 编码系数 I=2、O0=33、O1=123、O2=49、F=49 | 需原语系数定义及实际生成网表解释 | 不把编码当普通数学分频器猜输出，也不重新生成 IP |
| 配置与相机配置时钟 | IDF 请求 CLKOUT1=10、CLKOUT2=25MHz；顶层 clkout2->clk_25M，IDF CLKOUT3 disabled | 根 FDC 第753行却引用 clkout3；旧报告该 clock 0 loads，推断的 CLKOUT2 25MHz 有8 loads；run.log 有相机配置/ROM 的 STA-3011 no-clock 警告 | 不能仅因报告写 All Constraints Met 宣称配置链覆盖；待独立复现时查有效时钟/未约束端点 |
| CMOS PCLK | 根 FDC 第743-746行 11.9ns、二分频23.8ns | 旧报告同值，CMOS2 0 loads | 是约束，不是采样频率/IO 时序实测；两套源码存在不等于双路并行有效 |
| DDR | IDF 输入50、目标800；FDC DDR core10ns/IO2.5ns | 旧报告 core100MHz/IO400MHz | 配置量级对应，不证明匹配实物颗粒或当前已训练/稳定 |
| IO/CDC 范围 | 根 FDC 有多个异步 clock group；未检出根 FDC 的 set_input_delay/set_output_delay | 旧报告 no-clock/被排除范围需单独解释 | 没有完成外部 IO 时序与 CDC 签核；不能用异步分组掩盖握手或延迟风险 |
| 显示参数 | `source/rtl/sync_vg.v` H_TOTAL=1650、V_TOTAL=750，有效1280x720 | 37.125MHz /1650/750=30 为算术；不证明实际30fps | 输出配置、输入实际FPS、有效传输FPS须分别量测 |

根历史报告路径：
`E:/FPGA drive/HDMI_DDR3_OV5640/report_timing/hdmi_ddr_ov5640_top.rtr`

报告头为 Fabric Compiler 2022.2-SP6.1 build138931、2026-10-18 19:28:39、PGL50H/-6/FBG484，文字结果 All Constraints Met。没有找到把该根报告与**当前全部源/IP/FDC/工具输入哈希**绑定的清单，因此只登记历史文件事实，**当前输入的时序状态为未知**。v12 归档独立版本的审计不能替代根工程的时序证明。

后续若授权复现，最小签核范围应包括：有效 IP/网表时钟、CLKOUT2/3 对应、无时钟端点、外部采样相位/IO 延迟、异步组例外与真实 CDC、完整行帧数据归属；本轮未启动这些实验。

## 7. 实际检查、交付与停止点

本轮实际完成：目录/规则/Git 读取；四份 S0 审查文件复核；源码连接、IP XML/PLL/FDC/旧报告只读检查；PDF 提取/重点页图像核对；容量预检、全范围文件级复制、逐文件 SHA256；独立恢复及 Git fsck；保护文件和两份文档收尾检查。脚本保存在快照 `metadata/create_snapshot.ps1`、`verify_restore.ps1`、`finalize_s1.ps1`，结果以对应 JSON/JSONL 为准，不冒充 EDA 日志。

本轮没有执行软件视频金标准测试、RTL 仿真、综合、PNR/STA、下载、摄像头实测、网络传输、固化或工具许可证验证。S0 的测试结果没有改写成本轮新测试。

改动文件仅：

- `E:/FPGA drive/HDMI_DDR3_OV5640/docs/reintegration/03_baseline.md`
- `E:/FPGA drive/HDMI_DDR3_OV5640/docs/reintegration/07_video_interface.md`

建议下一项最小任务：**补齐这同一套实物的身份照片、原配适配器/现有接线证据，关闭第3节的型号与版本待确认项；继续不改 RTL、不换线、不改约束。**没有实物时可另行授权软件参考向量任务，但不自动执行，更不提前修复 DDR。

S1 状态：文档与恢复抽查已完成；实物核验及依赖它的签核待完成。**在此停止，不进入 S2。**
