param([ValidateSet('m403','m404')][string]$Version)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
try {
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'demo_launcher.ps1') -Action Stop -NoPause
 if($LASTEXITCODE -ne 0){throw '当前演示未能安全停止，未切换版本'}
 $path=Join-Path $PSScriptRoot 'config.json'
 $cfg=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
 $cfg | Add-Member -Force NoteProperty demo_ops "$Version/demo_ops.py"
 [IO.File]::WriteAllText($path,($cfg | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
 Write-Host "已切换到 $Version；SSH地址保持集中配置当前值。"
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'demo_launcher.ps1') -Action Start -NoPause
 if($LASTEXITCODE -ne 0){throw '版本已选择，但启动未完成，请查看操作报告'}
}catch{Write-Host $_.Exception.Message -ForegroundColor Red}
Read-Host '按回车关闭' | Out-Null
