param([Parameter(Mandatory)][string]$Build,
      [Parameter(Mandatory)][string]$Simulation,
      [Parameter(Mandatory)][string]$NativeSimulation)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$b=Get-Content "$Build/result.json" -Raw | ConvertFrom-Json
$s=Get-Content "$Simulation/result.json" -Raw | ConvertFrom-Json
$n=Get-Content "$NativeSimulation/result.json" -Raw | ConvertFrom-Json
if(-not $b.BuildPass -or -not $b.ExistingConstraintsMet -or -not $b.InputsUnchanged){throw 'Passing implemented build required'}
foreach($test in @($s,$n)){
    if($test.Verdict -ne 'PASS' -or -not $test.InputsUnchanged){throw 'Passing stable simulation required'}
}
$manifest=Get-Content "$Build/inputs.json" -Raw | ConvertFrom-Json
foreach($f in $manifest){if((Get-FileHash $f.Source).Hash -ne $f.SHA256){throw "Changed build input: $($f.Source)"}}
foreach($testDir in @($Simulation,$NativeSimulation)){
    $testInputs=Get-Content "$testDir/inputs.json" -Raw | ConvertFrom-Json
    foreach($p in $testInputs.PSObject.Properties){
        if((Get-FileHash -LiteralPath $p.Name).Hash -ne $p.Value){throw "Changed simulation input: $($p.Name)"}
    }
}
if((Get-FileHash $b.Release).Hash -ne $b.SHA256){throw 'Bitstream hash changed'}
$dest='E:/zhoumian/FPGA/JF/V5_1_MPI7001_800x480_DIAG'
if(Test-Path $dest){throw 'Delivery directory already exists'}
New-Item -ItemType Directory $dest | Out-Null
Copy-Item -LiteralPath $b.Release -Destination $dest
Copy-Item "$Build/report_timing/hdmi_ddr_ov5640_top.rtr" "$dest/timing.rtr"
Copy-Item "$Build/inputs.json" "$dest/build_inputs.json"
Copy-Item "$Simulation/result.json" "$dest/display_simulation.json"
Copy-Item "$NativeSimulation/result.json" "$dest/native_simulation.json"
Copy-Item "$repo/docs/reintegration/13_mpi7001_v5_1_diagnosis.md" "$dest/REPORT.md"
Copy-Item 'E:/zhoumian/FPGA/JF/checks/v5_1_change_review/scope_check.json' "$dest/scope_check.json"
Copy-Item 'E:/zhoumian/FPGA/JF/checks/v5_1_change_review/display_changes.diff' "$dest/display_changes.diff"
$release=[ordered]@{Name='V5_1_MPI7001_DIAG_KEY8_cmos1';Purpose='Display repair candidate and diagnostic probes, not board-accepted';SHA256=$b.SHA256;Size=(Get-Item $b.Release).Length;BuildDirectory=$Build;SimulationDirectory=$Simulation;NativeSimulationDirectory=$NativeSimulation;ExistingConstraintsMet=$true;BoardVerified=$false;Programmed=$false;FlashWritten=$false;SourceProject=$repo}
$release | ConvertTo-Json | Set-Content "$dest/release.json" -Encoding utf8
@"
# V5.1 显示排查版

烧录文件：V5_1_MPI7001_DIAG_KEY8_cmos1.sbit

这版修复已复现的首帧同步问题，保持 V5 时钟结构，增加显示端检查色条。
照片中的持续错块尚未确认根因，因此此包不是已通过上板验收的最终修复。

1. 给屏幕和开发板正常供电，接 HDMI-OUT。用 Fabric Configuration 关联本目录 SBIT 后 Program，不要选旧 V5。
2. 中间仍为 640×360 摄像头图像，屏幕信号仍为 800×480、约 59.93Hz。
3. 顶部依次为白、黄、青、绿、紫、红、蓝、黑八段色条；底部为细密黑白棋盘。最右黑段与背景连成一片是正常现象。
4. 色条和棋盘由输出端直接生成，不经过摄像头、算法和 DDR，应不随 KEY8 改变。
5. 先观察默认原图，再隔约一秒按一次并释放 KEY8，检查六档循环。

请反馈：顶部色条是否颜色正确、边缘整齐、没有杂点；中间画面是否仍错块；KEY8 灰度模式是否也错块。
底部棋盘经屏幕缩放/手机拍摄可能有摩尔纹，不能仅据照片条纹判断链路故障。

色条正常且中间异常：继续检查摄像头/处理/DDR 数据路径。
色条本身也异常：继续检查输出采样、MS7210、HDMI/屏幕及供电。
以上只是缩小范围，不是单独的根因结论。

已完成 RTL 定向检查和完整 PDS 构建；现有实现时序约束通过，不代表完整外部 IO/CDC 签核。
代理没有烧录硬件，没有写 Flash。

SHA256：$($b.SHA256)

原 V5 保留在 E:/zhoumian/FPGA/JF/V5_MPI7001_800x480。
"@ | Set-Content "$dest/README.md" -Encoding utf8
Write-Output $dest
