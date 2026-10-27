param([switch]$NoPause)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
$OutputEncoding=[Console]::OutputEncoding
try {
    $cfg=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw | ConvertFrom-Json
    if($cfg.ssh_host -notmatch '^[A-Za-z0-9._:-]+$' -or $cfg.ssh_user -notmatch '^[A-Za-z0-9_-]+$'){throw 'Invalid SSH host/user'}
    $b64=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'sample_net2.py')))
    $remote="sudo python3 -c 'import base64;exec(compile(base64.b64decode(`"$b64`"),`"<e1_sample>`",`"exec`"))' --interface eth0 --seconds 10"
    $dir=Join-Path $PSScriptRoot 'reports'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $output=Join-Path $dir ('E1_sample_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.txt')
    Write-Host '基础收发实验E1：采样10秒。需要时输入原有SSH密码及sudo密码。'
    Write-Host '发送20个ARP探测，读取硬件CRC与邻居；不更改IP、路由、邻居或现有服务。'
    $prior=$ErrorActionPreference;$ErrorActionPreference='Continue'
    try {
        & ssh.exe -t -p "$($cfg.ssh_port)" -o StrictHostKeyChecking=yes -o ConnectTimeout=8 "$($cfg.ssh_user)@$($cfg.ssh_host)" $remote 2>&1 | Tee-Object -FilePath $output
        $code=$LASTEXITCODE
    } finally {$ErrorActionPreference=$prior}
    Write-Host "采样输出：$output"
    if($code -ne 0){throw "SSH/采样退出码 $code；请回传输出文件。"}
} catch {Write-Host ('采样失败：'+$_.Exception.Message)}
finally {if(-not $NoPause){[void](Read-Host '按回车关闭')}}
