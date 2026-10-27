param([ValidateSet('m403','m404','m405','m405r2','m406')][string]$Version,[switch]$NoPause,[switch]$NoBrowser)
$ErrorActionPreference='Stop'
$failed=$false
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
try {
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'demo_launcher.ps1') -Action Stop -NoPause
 if($LASTEXITCODE -ne 0){throw '当前演示未能安全停止，未切换版本'}
 $path=Join-Path $PSScriptRoot 'config.json'
 $cfg=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
 $cfg | Add-Member -Force NoteProperty demo_ops "$Version/demo_ops.py"
 [IO.File]::WriteAllText($path,($cfg | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
 Write-Host "已切换到 $Version；SSH地址保持集中配置当前值。"
 $launchArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'demo_launcher.ps1'),'-Action','Start','-NoPause')
 if($NoBrowser){$launchArgs+='-NoBrowser'}
 & powershell.exe @launchArgs
 if($LASTEXITCODE -ne 0){throw '版本已选择，但启动未完成，请查看操作报告'}
}catch{$failed=$true;Write-Host $_.Exception.Message -ForegroundColor Red}
if(!$NoPause){Read-Host '按回车关闭' | Out-Null}
if($failed){exit 1}
