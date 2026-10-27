param([switch]$NoPause)
$ErrorActionPreference='Stop'
$report=Join-Path $PSScriptRoot 'reports'
$cfg=Get-Content (Join-Path $PSScriptRoot 'config.json') -Raw | ConvertFrom-Json
$listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
$listener.Start()
$cfg.local_port=$listener.LocalEndpoint.Port
$temp=Join-Path $report 'verification_config.json'
[IO.File]::WriteAllText($temp,($cfg | ConvertTo-Json),[Text.Encoding]::UTF8)
$exe=Join-Path $PSHOME 'powershell.exe'
$launcher=Join-Path $PSScriptRoot 'launcher.ps1'
try {
    & $exe -NoProfile -ExecutionPolicy Bypass -File $launcher -Action Start -ConfigPath $temp -NoPause -NoBrowser
    if($LASTEXITCODE -eq 0){throw 'Expected local port conflict was not detected'}
    $conflict=Get-ChildItem $report -Filter start_*.json | Sort-Object Name | Select-Object -Last 1 | Get-Content -Raw | ConvertFrom-Json
    if($conflict.error -notlike '*占用*'){throw 'Conflict report missing Chinese port explanation'}
    if(@($conflict.local_conflict | Where-Object {$_.pid -eq $PID}).Count -ne 1){throw 'Conflict owner PID incorrect'}
} finally {$listener.Stop()}
try {
    & $exe -NoProfile -ExecutionPolicy Bypass -File $launcher -Action Start -ConfigPath $temp -NoPause -NoBrowser
    if($LASTEXITCODE -ne 0){throw 'Owned tunnel/start failed'}
    $first=Get-ChildItem $report -Filter start_*.json | Sort-Object Name | Select-Object -Last 1 | Get-Content -Raw | ConvertFrom-Json
    & $exe -NoProfile -ExecutionPolicy Bypass -File $launcher -Action Start -ConfigPath $temp -NoPause -NoBrowser
    if($LASTEXITCODE -ne 0){throw 'Idempotent start failed'}
    $second=Get-ChildItem $report -Filter start_*.json | Sort-Object Name | Select-Object -Last 1 | Get-Content -Raw | ConvertFrom-Json
    if($first.remote.process.pid -ne $second.remote.process.pid){throw 'Duplicate service was created'}
    & $exe -NoProfile -ExecutionPolicy Bypass -File $launcher -Action Stop -ConfigPath $temp -NoPause
    if($LASTEXITCODE -ne 0){throw 'Stop failed'}
    if(Get-NetTCPConnection -LocalPort $cfg.local_port -State Listen -ErrorAction SilentlyContinue){throw 'Owned tunnel port not released'}
    & $exe -NoProfile -ExecutionPolicy Bypass -File $launcher -Action Stop -ConfigPath $temp -NoPause
    if($LASTEXITCODE -ne 0){throw 'Repeated stop failed'}
    [IO.File]::WriteAllText((Join-Path $report 'windows_tools_verification.json'),(@{
        ok=$true;time=(Get-Date -Format o);test_local_port=$cfg.local_port;reused_service_pid=$first.remote.process.pid;
        checks=@('Foreign local listener refused with owner PID','Own SSH tunnel created and HTTP session verified',
          'Second start same LIVE PID','Graceful stop and own tunnel release','Repeated stop succeeds');
        scope='Only an unused high local port was used; original external 18080 tunnel untouched; no network configuration changes'
    } | ConvertTo-Json),[Text.Encoding]::UTF8)
} finally {
    Write-Host '测试使用临时高端口；原18080外部转发未停止。默认配置未改。'
}
