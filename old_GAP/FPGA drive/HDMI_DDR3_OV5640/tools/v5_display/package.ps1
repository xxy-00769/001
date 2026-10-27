param([Parameter(Mandatory)][string]$Build,[Parameter(Mandatory)][string]$Simulation)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$b=Get-Content "$Build/result.json" -Raw | ConvertFrom-Json
$s=Get-Content "$Simulation/result.json" -Raw | ConvertFrom-Json
if(-not $b.BuildPass -or -not $b.ExistingConstraintsMet -or -not $b.InputsUnchanged -or $s.Verdict -ne 'PASS' -or -not $s.InputsUnchanged){throw 'Completed passing build and simulation required'}
$manifest=Get-Content "$Build/inputs.json" -Raw | ConvertFrom-Json
foreach($f in $manifest){if((Get-FileHash $f.Source).Hash -ne $f.SHA256){throw "Changed input: $($f.Source)"}}
if((Get-FileHash $b.Release).Hash -ne $b.SHA256){throw 'Bitstream hash changed'}
$dest='E:/zhoumian/FPGA/JF/V5_MPI7001_800x480'
if(Test-Path $dest){throw 'Delivery directory already exists'}
New-Item -ItemType Directory $dest | Out-Null
Copy-Item -LiteralPath $b.Release -Destination $dest
Copy-Item "$Build/report_timing/hdmi_ddr_ov5640_top.rtr" "$dest/V5_timing.rtr"
Copy-Item "$Build/inputs.json" "$dest/build_inputs.json"
Copy-Item "$Simulation/result.json" "$dest/simulation_result.json"
Copy-Item "$repo/docs/reintegration/12_mpi7001_display_v5.md" "$dest/V5_开发与验证记录.md"
$release=[ordered]@{Name='V5_MPI7001_800x480_KEY8_cmos1';SHA256=$b.SHA256;Size=(Get-Item $b.Release).Length;BuildDirectory=$Build;SimulationDirectory=$Simulation;ExistingConstraintsMet=$true;BoardVerified=$false;Programmed=$false;FlashWritten=$false;SourceProject=$repo}
$release | ConvertTo-Json | Set-Content "$dest/release.json" -Encoding utf8
@"
# V5 MPI7001 屏幕显示适配

烧录文件：V5_MPI7001_800x480_KEY8_cmos1.sbit

1. 屏幕独立供电，连接开发板 HDMI-OUT。
2. 在 Fabric Configuration 中通过 Assign New Configuration File 选择本目录的 V5 位流，再执行 Program。
3. 默认显示原图；视频内容为居中的 640×360，屏幕信号为 800×480、约 59.93Hz，四周黑边是设计预期。
4. KEY8 每按一次并释放，依次切换原图、灰度、中值滤波、Sobel、颜色候选、旧诊断，再回原图。

已完成定向仿真及 PDS 全流程，最终报告为 All Constraints Met（现有约束覆盖范围）。尚未上板验证，屏幕实际点亮和显示效果等待用户反馈。没有写 Flash，JTAG 配置断电后通常需要重新下载。

若不显示，请区分屏幕提示“无信号”还是“有信号但全黑”，并记录 HDMI 初始化 LED、摄像头连接及烧录文件名。

SHA256：$($b.SHA256)

源工程：$repo/impl.pds
完整构建：$Build
仿真证据：$Simulation
"@ | Set-Content "$dest/烧录与验收说明.md" -Encoding utf8
Write-Output $dest
