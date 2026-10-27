param([Parameter(Mandatory)][string]$Build,[Parameter(Mandatory)][string]$Check)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$b=Get-Content "$Build/result.json" -Raw | ConvertFrom-Json
$c=Get-Content "$Check/result.json" -Raw | ConvertFrom-Json
if(-not $b.BuildPass -or -not $b.ExistingConstraintsMet -or -not $b.InputsUnchanged){throw 'Build not accepted'}
if($c.Verdict -ne 'PASS' -or -not $c.InputsUnchanged){throw 'Display checks not accepted'}
foreach($f in (Get-Content "$Build/inputs.json" -Raw | ConvertFrom-Json)){if((Get-FileHash -LiteralPath $f.Source).Hash -ne $f.SHA256){throw "Changed build input $($f.Source)"}}
$ci=Get-Content "$Check/inputs.json" -Raw | ConvertFrom-Json
foreach($p in $ci.PSObject.Properties){if((Get-FileHash -LiteralPath $p.Name).Hash -ne $p.Value){throw "Changed check input $($p.Name)"}}
if((Get-FileHash -LiteralPath $b.Release).Hash -ne $b.SHA256){throw 'Bit hash mismatch'}
$dest='E:/zhoumian/FPGA/JF/V5_2_MPI7001_800x480_BRIGHT'
if(Test-Path $dest){throw 'Destination already exists'}
New-Item -ItemType Directory -Path $dest | Out-Null
Copy-Item -LiteralPath $b.Release -Destination $dest
Copy-Item "$Build/report_timing/hdmi_ddr_ov5640_top.rtr" "$dest/timing.rtr"
Copy-Item "$Build/inputs.json" "$dest/build_inputs.json"
Copy-Item "$Check/result.json" "$dest/display_check.json"
Copy-Item "$repo/docs/reintegration/14_mpi7001_v5_2_clean_bright.md" "$dest/REPORT.md"
Copy-Item 'E:/zhoumian/FPGA/JF/checks/v5_2_scope/scope.json','E:/zhoumian/FPGA/JF/checks/v5_2_scope/diff.txt' -Destination $dest
[ordered]@{Name='V5_2_MPI7001_BRIGHT_KEY8_cmos1';SHA256=$b.SHA256;Size=(Get-Item $b.Release).Length;Build=$Build;DisplayCheck=$Check;ExistingConstraintsMet=$true;BoardVerified=$false;Programmed=$false} | ConvertTo-Json | Set-Content "$dest/release.json" -Encoding utf8
@"
# V5.2 显示版

烧录本目录 V5_2_MPI7001_BRIGHT_KEY8_cmos1.sbit。保持原有硬件连接和烧录方式。

顶部彩条、底部检查格已移除。边缘为黑色，中央仍为 640×360 图像。
输出端三通道统一增加约 12.5%，亮部饱和封顶，黑色不变；算法及 DDR 内图像不变。KEY8 模式、屏幕时序保持原样。

完整编译、现有时序约束和显示端自动检查通过。新位流未上板确认，也未由代理烧录。
烧录后确认画面稳定、黑边无彩条、亮度是否合适即可。

SHA256: $($b.SHA256)
稳定的旧版 V5.1 保留在 E:/zhoumian/FPGA/JF/V5_1_MPI7001_800x480_DIAG。
"@ | Set-Content "$dest/README.md" -Encoding utf8
Write-Output $dest
