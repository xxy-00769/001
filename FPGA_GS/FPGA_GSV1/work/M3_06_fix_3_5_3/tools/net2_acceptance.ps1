param([switch]$NoPause)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$OutputEncoding=[Console]::OutputEncoding
$report=$null
try {
    $cfg=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw | ConvertFrom-Json
    if($cfg.remote_dir -notmatch '^/[A-Za-z0-9_./-]+$' -or $cfg.ssh_host -notmatch '^[A-Za-z0-9._:-]+$' -or $cfg.ssh_user -notmatch '^[A-Za-z0-9_-]+$'){throw 'SSH configuration format invalid'}
    $ssh=(Get-Command ssh.exe -ErrorAction Stop).Source
    $b64=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'net2_acceptance_probe.py')))
    $c64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($cfg | ConvertTo-Json -Compress)))
    $remote="cd '$($cfg.remote_dir)' && .venv/bin/python -c `"import base64;exec(compile(base64.b64decode('$b64'),'<net2_read_only>','exec'))`" --config $c64"
    $dir=Join-Path $PSScriptRoot 'reports'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $report=Join-Path $dir ('net2_acceptance_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff')+'.json')
    Write-Host '只读检查约4秒；需要时输入现有SSH密码。不会修改网络或启动第二个服务。'
    $prior=$ErrorActionPreference;$ErrorActionPreference='Continue'
    try {
        & $ssh '-p' "$($cfg.ssh_port)" '-o' 'StrictHostKeyChecking=yes' '-o' 'ConnectTimeout=8' '-o' 'ConnectionAttempts=1' "$($cfg.ssh_user)@$($cfg.ssh_host)" $remote > $report
        $code=$LASTEXITCODE
    } finally {$ErrorActionPreference=$prior}
    if($code -ne 0){throw "SSH检查失败，退出码 $code；未改变任何网络配置。"}
    $r=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
    [IO.File]::WriteAllText($report,($r | ConvertTo-Json -Depth 40),(New-Object Text.UTF8Encoding($true)))
    foreach($entry in @(@('automatic_arp','自动ARP'),@('online','心跳在线'),@('heartbeat_received','采样窗收到心跳'),@('new_complete_front','采样窗收到完整前摄'),@('hardware_crc_not_growing','主机硬件CRC错误无增长'))){
        $value=$r.checks.($entry[0]);$label=if($null -eq $value){'未知'}elseif($value){'通过'}else{'未通过'}
        Write-Host ($entry[1]+'：'+$label)
    }
    Write-Host ('实收前摄fps：'+$r.front_receive_fps+'；采样窗秒：'+$r.window_seconds)
    Write-Host ('主机硬件计数增量：'+($r.hardware_delta | ConvertTo-Json -Compress))
    if($r.temporary_static_neighbor_detected){Write-Host '检测到静态邻居；不能据此判定自动ARP通过。本工具未更改它。'}
    Write-Host $(if($r.pass_all){'本次通信采样验收通过；请看预览确认CAM0彩色实景。'}else{'本次尚未全部通过或有未知项；请回传下面这一个JSON。'})
    Write-Host "结果文件：$report"
} catch {
    Write-Host ('检查失败：'+$_.Exception.Message)
    if($report){Write-Host "已有输出：$report"}
} finally {
    if(-not $NoPause){[void](Read-Host '按回车关闭')}
}
