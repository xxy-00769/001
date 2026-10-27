# MES50HP 本机开发环境检查与配置教程

检查日期：2026-10-20。历史资料位置：`E:/zhoumian/FPGA/历史工程/FPGA drive`。本文用于在当前 Windows 电脑复现历史工程并继续开发。

## 1. 检查结论：现在缺什么

**PDS 已经安装，不需要从头装一遍。优先补齐 ModelSim、确认本机许可证和下载器驱动，再调整旧工程脚本路径。**

| 项目 | 历史电脑依据 | 当前电脑实际情况 | 下一步 |
|---|---|---|---|
| Windows | 历史构建使用 Windows 路径与 PowerShell | Windows 11 专业版 64 位，约 32GB 内存 | 可继续使用 |
| PDS | 2022.2-SP6.1，build 138931 | 已安装 2022.2-SP6.4，build 146967，命令行帮助执行成功 | 先保留 SP6.4，单独验证兼容性 |
| ModelSim | SE-64 10.7，实际仿真版本日志可核对 | PATH、卸载注册表及已检查的软件目录未发现 | 需要安装，或提供已有安装位置进一步检查 |
| Pango 仿真原语 | 旧 SP6.1 下的厂商库 | SP6.4 的 `GTP_GRS.v`、`GTP_DRM18K.v` 存在 | 仿真时显式指定新库路径 |
| PDS 许可证 | 旧日志显示曾成功签出，但也曾有即将到期警告 | 未发现安装目录内 `.lic`，未发现当前进程相关许可证环境变量 | 本机授权待配置/核验；不能据此断言所有授权方式都不存在 |
| 下载器驱动 | 旧机有配置下载记录 | 当前未检测到在线 Pango/JTAG/FTDI 等相关设备；PDS 附带驱动安装文件 | 接下载器后检查，必要时安装 |
| Python | 协议工具要求 3.10+；旧脚本绑定旧用户目录 | 默认 `python`/`py -3` 是 3.9.9；另有 3.14.4 和工具专用环境 | 协议工具用明确路径，不用默认 3.9 |
| PowerShell | 脚本包含 `[IO.Path]::GetRelativePath`，需现代运行环境 | 当前执行检查使用 PowerShell 7.6.5 | 开发脚本使用 PowerShell 7 |
| Git | 历史工程按版本管理和输入哈希记录 | Git 2.53.0.windows.2 可用 | 无需重装 |
| 编辑器 | 不绑定特定编辑器 | VS Code 有安装记录；`code` 命令实际指向 Qoder | 选择自己使用的编辑器，核对打开的目录 |
| Visual C++ 运行库 | 原 PDS 安装教程要求运行库 | 当前已有 VC++ 2022 x64/x86 14.51 | 无需因旧教程重复安装 VS2017；以工具启动检查为准 |
| C 编译器 | 历史便携 C 解析器有 GCC 测试命令 | PATH 和已检查目录未发现可用 GCC/Clang/MSVC 命令 | 仅需要验证 C 解析器时再装，不影响 FPGA/Python 主线 |
| Wireshark | 网络阶段可用来抓包 | PATH、卸载记录和已检查目录未发现 | 实体网络排障前建议安装，不是编译前提 |
| 算法软件包 | 旧 `road_first` 有专用依赖 | Codex 配套 Python 3.12 有 NumPy/Pillow，未找到 ONNX Runtime/OpenCV | 算法实验时另建环境，暂不阻塞 FPGA |

“未发现”的结论限于检查过的命令、注册表、旧路径和常见软件位置，不是逐盘扫描所有隐藏/便携软件。电脑有 Realtek 有线千兆网卡，目前未接线，协商速率尚未验证。无线连接正常，不需要修改它。

本轮未安装软件、修改环境变量、运行历史构建脚本、改动 RTL/约束或下载板卡。PDS 只在独立检查目录运行了 `-help`，没有验证综合许可、完整编译或上板。

## 2. 历史电脑到底用什么环境

### 2.1 FPGA 工具链

以下结论相互印证，并非只看 README：

- `build.bat` 中 `PDS_BIN` 为 `D:/PDS/PDS_2022.2-SP6.1/bin`。
- `flow.tcl` 标明 SP6.1，配置 Logos、PGL50H、速度等级 -6、FBG484。
- `.pds` 文件头记录 `2022.2-SP6.1 build 138931`。其中旧的 `2022.1` 流程标识不能单独用来推断实际工具版本。
- `tests/pnr_help.txt` 记录同一版本与旧许可证签出信息。

### 2.2 仿真

旧脚本使用 `D:/PDS/Modelsim/win64` 下的 `vlib.exe`、`vmap.exe`、`vlog.exe`、`vsim.exe`。历史 `tmp/video_modes/20261019_204949_809_3bc5e988/version.log` 明确记录 ModelSim SE-64 10.7 编译器。

仿真还引用 PDS 安装目录的厂商原语，不能只安装 ModelSim 而不配置库。历史原厂 DDR/PLL 仿真记录中曾使用 `-novopt` 绕开旧版本优化阶段崩溃；这是具体测试的兼容措施，不应给所有测试无条件追加，更不能假定新版 Questa 支持同样参数。

### 2.3 主机程序

普通诊断与结果解析要求 Python 3.10+，使用标准库。部分旧图像参考测试另需 NumPy、Pillow。`host/road_first/requirements.txt` 记录：

```text
numpy==2.3.5
Pillow>=11,<13
onnxruntime==1.23.2
```

这些依赖属于研究算法分支，不是所有 FPGA 操作的前提。当前证据不能确定旧电脑所有 Python 环境的精确版本与包清单；脚本中出现过 Codex 配套 Python 的绝对路径，迁移时必须替换。

## 3. 第一步：保留历史目录，建立当前开发目录

历史目录作为参考保留。建议当前工作副本使用较短、无空格和中文的路径，例如：

```text
E:/FPGA_Work/MES50HP/
    HDMI_DDR3_OV5640/    工作工程
    tmp/                新的仿真与构建输出
    licenses/           本机有效授权（不提交到版本库）
```

工作副本应包含源码、约束、`.pds`、`flow.tcl`、IP 的配置及所需生成文件、测试与工具。不要仅复制 `.v`；也不必为了开发把整个历史 `tmp`、归档位流和模型复制多份。若原仓库有本地改动、未跟踪文件或外部依赖，需要一并确认，不能只用 Git 已提交内容代替当前工作状态。

当前历史路径有空格和中文，本轮读取正常，不表示旧 PDS 全流程已兼容。工作副本迁移后，先检查各模块初始化文件、IP 路径、Tcl 和脚本。不要对整个目录做无差别字符串替换；历史报告中的旧路径是证据，不应伪装改写成新执行结果。

## 4. 第二步：确认已安装的 PDS 和本机授权

### 4.1 现有 PDS 可以继续用

当前安装路径：

```text
E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4
```

在 PowerShell 中检查：

```powershell
$pdsRoot = 'E:\XUEXI\FPGA_PDS\PDS_2022.2-SP6.4'
Test-Path "$pdsRoot\bin\pds_shell.exe"
& "$pdsRoot\bin\pds_shell.exe" -help
```

本轮已执行帮助命令，输出 `2022.2-SP6.4 build 146967`。因此，“PDS 不在 PATH”不等于未安装，使用完整路径就可以调用。

### 4.2 授权如何配置

旧机器的节点锁定许可证不能预设适用于这台机器。向板卡供应商或紫光同创正规渠道申请/确认适用于本机、器件和相应综合工具的有效许可。申请所需的机器信息按对方工具和要求采集。

取得本机许可后，按照 [PDS 安装指导](../资料/盘古50K开发板资料/盘古50K开发板/1_Demo_document/工具使用篇/01_PDS安装指导手册.pdf) 配置。该教程明确给出 PDS 变量 `PANGO_LICENSE_FILE`；若流程实际使用 OEM Synplify，还需要对应的 `SNPSLMD_LICENSE_FILE` 授权，不能只装运行库就认为综合工具可用。

以下命令仅在已经把真实有效许可放到该路径后使用，文件名是示例：

```powershell
$licensePath = 'E:\FPGA_Work\MES50HP\licenses\pds_local.lic'
if (-not (Test-Path -LiteralPath $licensePath)) {
    throw '请先放入适用于本机的有效许可证，并修改实际路径。'
}
[Environment]::SetEnvironmentVariable('PANGO_LICENSE_FILE', $licensePath, 'User')
$env:PANGO_LICENSE_FILE = $licensePath
```

重开 PDS 和终端后生效。帮助命令成功不能证明授权可用，授权验收应是一个小型工程真正完成所需综合和后端流程。遇到 license checkout failed，先检查许可种类、主机绑定、有效期和工具支持，不通过反复重装解决。

旧 Lite 安装包不需要许可证的目录标记，不代表它与当前工程的器件、IP 和功能完全匹配，因此不推荐直接用 Lite 替换现有 SP6.4。

### 4.3 SP6.4 与旧 SP6.1 怎么选

先保留当前 SP6.4，复制一个工作工程逐级检查：打开→源码解析→综合→布局布线与时序→位流。保存版本差异和警告，不能只看到 `.sbit` 就确认迁移成功。

本轮没有实测 SP6.4 对旧工程全部 IP、约束和后端结果的兼容性。若复现出现确定的版本问题，再获取正规的 SP6.1 安装包，按安装器支持情况隔离安装或使用另一套环境。当前资料库已找到 SP6.4 和 SP1 Lite 包，未在已检查目录找到 SP6.1 安装包。

## 5. 第三步：安装 ModelSim 并配置厂商库

### 5.1 获取与安装

历史版本是 ModelSim SE-64 10.7。优先通过学校授权、供应商支持或软件正规渠道获得可用仿真器及许可；如果只能获得较新 ModelSim/Questa，先确认 PDS 支持与加密 IP 兼容，再测试旧脚本，不把名字相近视为完全可替代。

本工作空间未找到可直接确认的 ModelSim 安装包。PDS 中有联合仿真教程，不意味着已经包含完整 ModelSim 安装程序或许可。

安装到路径简洁的位置，例如 `E:/FPGA_Tools/ModelSim`。安装完成后找到实际包含以下文件的目录，具体可能叫 `win64` 或 `win64pe`，不要照抄旧路径：

```text
vlib.exe
vmap.exe
vlog.exe
vsim.exe
```

在 PowerShell 中用实际路径检查：

```powershell
$modelSimBin = 'E:\FPGA_Tools\ModelSim\win64'  # 改成真实目录
foreach ($toolName in 'vlib.exe','vmap.exe','vlog.exe','vsim.exe') {
    if (-not (Test-Path (Join-Path $modelSimBin $toolName))) {
        throw "缺少 $toolName，请检查安装目录。"
    }
}
& "$modelSimBin\vlog.exe" -version
& "$modelSimBin\vsim.exe" -version
```

能够显示版本还不等于运行仿真时许可签出成功，需要实际建立工作库、编译小测试台并运行退出。

### 5.2 两种库配置方式

**使用现有 PowerShell 仿真脚本：**脚本中已经列出原语源文件并编译时，传入当前 PDS 的 `PrimitiveLibrary`，无需为了同一个测试重复建立全部器件库。

当前可用原语目录：

```text
E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation
```

**使用 PDS 图形界面联合仿真：**按 [PDS 与 ModelSim 联合仿真教程](../资料/盘古50K开发板资料/盘古50K开发板/1_Demo_document/工具使用篇/04_PDS与modelsim联合仿真.pdf)，在 Compile Simulation Libraries 中选择仿真器位置、Verilog、Logos 对应库和输出目录。注意本板是 Logos/PGL50H，不是其他示例的 Logos-2。界面以实际安装版为准。

初次验证从不含 DDR PHY 的简单测试开始，再运行使用厂商原语的测试，最后验证涉及加密 DDR/PLL 的完整测试。任何一级失败，都保留原日志，区别语法错误、缺原语、许可失败和仿真器兼容问题。

## 6. 第四步：Python 环境按用途选择

### 6.1 诊断通信：现成环境已经够用

当前 S5 工具的 Python 为：

```text
E:/code/StreamLab/tools/MES50HP_S5_tools/.venv/Scripts/python.exe
```

它使用 Python 3.14.4，本机此前已通过回环模拟收发。无需重新安装第三方包，也不要用默认的 `python` 或 `py -3`，因为它们当前会选 3.9。

检查：

```powershell
$pythonExe = 'E:\zhoumian\FPGA\tools\MES50HP_S5_tools\.venv\Scripts\python.exe'
& $pythonExe --version
```

此环境位于 S5 工具目录，可以用于相同标准库要求的诊断脚本；不要将它当作已经安装图像算法依赖的全项目环境。

### 6.2 图像参考或算法：以后另建 Python 3.12 环境

需要 NumPy/Pillow 的参考测试，或继续运行旧 ONNX 模型时，建议另装官方 Python 3.12 x64，并建立独立环境。旧包固定版本的 Windows wheel 对 Python 3.14 支持不能预设，因此不要把研究依赖强塞进当前 S5 环境。

安装 Python 3.12 后，先运行 `py -0p` 确认解释器选择，再在实际工作副本中执行：

```powershell
Set-Location 'E:\FPGA_Work\MES50HP\HDMI_DDR3_OV5640'
py -3.12 -m venv .venv
$pythonExe = Join-Path $PWD '.venv\Scripts\python.exe'
& $pythonExe -m pip install --upgrade pip
& $pythonExe -m pip install 'numpy==2.3.5' 'Pillow>=11,<13'
& $pythonExe -c "import sys,numpy,PIL; print(sys.version); print(numpy.__version__,PIL.__version__)"
```

仅在继续旧研究模型时，再运行：

```powershell
& $pythonExe -m pip install -r '.\host\road_first\requirements.txt'
& $pythonExe -c "import onnxruntime; print(onnxruntime.__version__)"
```

OpenCV、RKNN、CUDA、PyTorch 不属于当前 FPGA 基线的必装项。香橙派部署、视频接收显示和训练模型时分别按实际任务安装。本轮没有为你安装 Python 3.12 或这些包。

## 7. 第五步：修改工作副本的工具路径

安装完软件还不够，旧脚本仍然指向旧机器。

| 位置 | 旧值/问题 | 处理 |
|---|---|---|
| `build.bat` | `D:/PDS/PDS_2022.2-SP6.1/bin` | 工作副本改成实际 PDS bin |
| 多个 `run.ps1` | `D:/PDS/Modelsim/win64` | 优先使用 `-ModelSim` 参数覆盖 |
| 部分 `run.ps1` | SP6.1 仿真库 | 使用 `-PrimitiveLibrary` 覆盖成实际安装版 |
| 仿真/构建脚本 | `E:/FPGA drive/tmp/...` | `-OutputParent` 改成当前工作目录同级的 `tmp` 下 |
| `tools/s5_diag/run.ps1` | 旧用户 `19511` 的 Python | 传入 `-Python` |
| 构建脚本/历史 manifest | 旧源文件和仿真证据绝对路径 | 重新生成当前证据，不批量改写历史结果 |

部分脚本要求输出必须位于“工程父目录的 tmp”内，所以输出参数不是任意目录都能用。这是路径校验，不是工具未安装。

下面以工作副本和已经安装好的仿真器为前提，给出 S5 应用层仿真调用示例：

```powershell
Set-Location 'E:\FPGA_Work\MES50HP\HDMI_DDR3_OV5640'
$modelSimBin = 'E:\FPGA_Tools\ModelSim\win64'  # 改成实际目录
$pythonExe = 'E:\zhoumian\FPGA\tools\MES50HP_S5_tools\.venv\Scripts\python.exe'
.\tools\s5_diag\run.ps1 `
    -ModelSim $modelSimBin `
    -Python $pythonExe `
    -OutputParent 'E:\FPGA_Work\MES50HP\tmp\s5_diag'
```

这会创建新测试目录并执行主机测试和 RTL 仿真，不是本轮已经跑过的结果，也不能证明实体网口已通。

其他脚本的参数不完全相同，先读开头 `param(...)` 再运行。当前 KEY8 相关 `tools/video_modes/run.ps1` 支持 `-ModelSim`、`-PrimitiveLibrary`、`-OutputParent` 等参数，可据实际路径适配。

PowerShell 7 已可用，应在该终端运行脚本；旧 Windows PowerShell 5.1 可能不支持某些 .NET API。检查：

```powershell
$PSVersionTable.PSVersion
```

如果只因从网络下载的 `.ps1` 被标记而阻止执行，先核对脚本来源与内容，必要时仅对指定可信文件解除阻止。不要为了运行整个工程全局设置 Unrestricted。

### 暂时别直接双击旧 build.bat

它不只是检查环境：会删除并重新生成 `impl.tcl`，也会删除通用输出目录中同名旧位流，然后运行构建。先保留历史目录、选好工作副本、修好路径和授权，再执行。

`flow.tcl` 是构建模板，`impl.tcl` 可能被 PDS 追加内容；不要把历史 `impl.tcl` 当成需要不断手改的主配置。完整构建与仿真都应保留本轮独立日志。

## 8. 第六步：下载器驱动与网口

### 8.1 下载器

当前 PDS 已附带 USB 驱动文件：

```text
E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/driver
```

接入板卡配套下载器、正确供电后，在设备管理器检查设备是否出现以及是否有黄色警告。若缺驱动，优先用当前 PDS 安装器的 USB Cable Driver 组件或供应商适用于该下载器的正规驱动；是否用本目录 `dpinst-amd64.exe` 应先核对下载器和系统兼容性，不能给不相关 USB 设备强制替换驱动。

验收先打开 PDS Configuration 扫描 JTAG 链，确认器件正确。扫描不等于烧录，不必在环境核对时覆盖当前位流。后续选定基线后再下载，Flash 固化和断电重启单独验收。

教程：[FPGA/CPLD 下载与固化](../资料/盘古50K开发板资料/盘古50K开发板/1_Demo_document/工具使用篇/05_FPGA&CPLD的下载与固化_v1.1.pdf)。其中旧教程涉及并口驱动的步骤，只对实际使用的并口下载器考虑；USB 下载器不需要为了凑齐步骤装并口驱动。无需全局关闭防护软件。

### 8.2 网口

本机已有 Realtek PCIe GbE 千兆网卡，目前显示未连接。用 Cat5e/Cat6 网线连接 FPGA 实际使用的网口，或通过千兆交换机连接，届时检查是否协商到 1Gbps。

现阶段不改 IP、Wi-Fi、网桥或防火墙。等 FPGA 交付真正接通 MAC/PHY 的位流，再按该版本实际地址设置有线网卡。现有 S5 软件模拟通过，不代表目前 FPGA 位流能够回复 UDP。

网络故障排查时再装 Wireshark（需要抓包时安装配套 Npcap），选择对应有线网卡抓 `arp or udp.port == 8000`；端口按最终发布配置调整。没有 ICMP 实现时不能仅凭 ping 不通判断工具安装失败。

## 9. 按这份清单验收环境

- [x] 当前 PDS SP6.4 可执行文件存在，`-help` 正常，版本已核实。
- [x] PDS 配套关键仿真原语文件存在。
- [x] Git 可用，当前检查使用 PowerShell 7。
- [x] S5 独立 Python 3.14 环境存在，此前回环收发已验证。
- [x] VC++ x64/x86 运行库已有安装记录。
- [ ] 本机 PDS/实际综合工具授权有效，小工程可完成所需流程。
- [ ] ModelSim/兼容仿真器安装完成，许可与小仿真验证通过。
- [ ] 厂商原语与旧项目测试能在新路径运行。
- [ ] 工作副本的工具、输出、Python 路径已经适配。
- [ ] 当前源码通过 SP6.4 重建，版本差异、资源与时序有记录。
- [ ] 下载器驱动正确，JTAG 可以识别实际器件。
- [ ] 联网时网卡协商到千兆；实体诊断在对应 FPGA 位流上测试。

最先处理的顺序：**确认本机 PDS 授权 → 安装 ModelSim → 适配工作副本路径 → 跑小测试 → 验证厂商库 → 重建视频工程 → 扫描/下载上板。**

## 10. 本次结论的证据入口

- [旧 build.bat](<../历史工程/FPGA drive/HDMI_DDR3_OV5640/build.bat>)：旧 PDS 路径和构建副作用。
- [旧 flow.tcl](<../历史工程/FPGA drive/HDMI_DDR3_OV5640/flow.tcl>)：器件和版本配置。
- [旧 ModelSim 版本日志](<../历史工程/FPGA drive/tmp/video_modes/20261019_204949_809_3bc5e988/version.log>)：10.7 编译器。
- [旧 PDS 帮助记录](<../历史工程/FPGA drive/HDMI_DDR3_OV5640/tests/pnr_help.txt>)：SP6.1 build 138931 与历史许可状态。
- [S5 脚本](<../历史工程/FPGA drive/HDMI_DDR3_OV5640/tools/s5_diag/run.ps1>)：工具参数和旧 Python 绝对路径。
- [研究分支依赖](<../历史工程/FPGA drive/HDMI_DDR3_OV5640/host/road_first/requirements.txt>)：算法软件包范围。
- [本机 PDS 帮助输出](../tmp/analysis/environment_audit_20261020/pds_help.log)：SP6.4 build 146967 实际启动证据。
- [已部署 S5 工具说明](../tools/MES50HP_S5_tools/本机使用说明.md)：Python 环境与软件模拟验证边界。

历史工程文档中有旧的架构决策，不能代替最新用户方案。当前讨论已调整为 FPGA HDMI 合成显示、优先传前摄到香橙派；这不改变本教程的基本工具需求，教程也没有修改工程来实现该架构。
