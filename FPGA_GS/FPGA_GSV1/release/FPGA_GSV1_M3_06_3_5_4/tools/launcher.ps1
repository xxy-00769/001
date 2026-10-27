param(
    [ValidateSet('Start','Stop','Diagnose')][string]$Action = 'Start',
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'),
    [switch]$NoPause,
    [switch]$NoBrowser
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$Utf8 = New-Object System.Text.UTF8Encoding($true)
$StateDir = Join-Path $PSScriptRoot 'state'
$ReportDir = Join-Path $PSScriptRoot 'reports'
New-Item -ItemType Directory -Force $StateDir,$ReportDir | Out-Null
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$Trace = New-Object System.Collections.Generic.List[string]
$Result = [ordered]@{tool_version='M4-01-operator-v1';action=$Action;computer_time=(Get-Date -Format o);ok=$false}
$OpLock = $null

function Say([string]$Text) { Write-Host $Text; $Trace.Add($Text) }
function Save-Json($Object,[string]$Path) { [IO.File]::WriteAllText($Path,($Object | ConvertTo-Json -Depth 40),$Utf8) }
function Get-LocalListeners {
    return @(Get-NetTCPConnection -LocalPort ([int]$Cfg.local_port) -State Listen -ErrorAction SilentlyContinue |
        ForEach-Object {
            $owner = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)" -ErrorAction SilentlyContinue
            [pscustomobject]@{address=$_.LocalAddress;port=$_.LocalPort;pid=$_.OwningProcess;
                name=$owner.Name;command_line=$owner.CommandLine;creation_date=[string]$owner.CreationDate}
        })
}
function Get-Http {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$($Cfg.local_port)/status.json?t=$([DateTimeOffset]::Now.ToUnixTimeMilliseconds())" -UseBasicParsing -TimeoutSec 3
        $content=[Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
        return [pscustomobject]@{ok=$true;status=[int]$r.StatusCode;data=($content | ConvertFrom-Json)}
    } catch { return [pscustomobject]@{ok=$false;error=$_.Exception.Message} }
}
function Invoke-Remote([string]$RemoteAction) {
    $json = $Cfg | ConvertTo-Json -Compress -Depth 10
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    # Paths containing shell quoting characters are refused below; configuration is data in base64.
    $command = "cd '$($Cfg.remote_dir)' && .venv/bin/python '$($Cfg.remote_tool)' $RemoteAction --config $b64"
    $file = Join-Path $StateDir "reply_$Stamp.json"
    Say "通过SSH执行 $RemoteAction；需要认证时请在终端输入密码（不保存）。"
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & $Ssh @SshArgs $Target $command > $file; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $old }
    if ($code -ne 0) { throw "SSH不可达、认证/主机校验失败，或远端工具无法执行（退出码$code）。请核对配置和上面的SSH提示；首次主机身份需核对后用正常ssh接受，工具不会关闭校验。" }
    try { return (Get-Content -LiteralPath $file -Raw | ConvertFrom-Json) }
    catch { throw "远端输出不是有效JSON，请查看 $file" }
}
function Get-OwnedTunnel {
    $record = Join-Path $StateDir 'tunnel.json'
    if (-not (Test-Path -LiteralPath $record)) { return $null }
    $saved = Get-Content -LiteralPath $record -Raw | ConvertFrom-Json
    if ($saved.stopped_at) { return $null }
    $now = Get-CimInstance Win32_Process -Filter "ProcessId=$($saved.pid)" -ErrorAction SilentlyContinue
    if (-not $now) {
        $saved | Add-Member -NotePropertyName stopped_at -NotePropertyValue (Get-Date -Format o) -Force
        Save-Json $saved $record
        return $null
    }
    if (-not $now.CommandLine -or $now.CommandLine -ne $saved.command_line -or [string]$now.CreationDate -ne $saved.creation_date -or $now.Name -ne 'ssh.exe') {
        throw '记录的SSH PID身份不能确认或已变化；拒绝停止/接管该进程。'
    }
    return $now
}
function Same-Service($Http,$RemoteStatus) {
    return ($Http.ok -and $Http.data.mode -eq 'LIVE_FRONT' -and $Http.data.link -and
        $RemoteStatus.ok -and $RemoteStatus.data.link -and
        $Http.data.link.session -eq $RemoteStatus.data.link.session)
}
function Previously-VerifiedForward($Listeners) {
    # Keep externally created SSH tunnels after Stop. A previous successful
    # session match plus unchanged SSH PID/creation time permits later reuse.
    foreach($file in @(Get-ChildItem -LiteralPath $ReportDir -Filter 'start_*.json' | Sort-Object Name -Descending)) {
        try {$r=Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json}catch{continue}
        if(-not $r.ok -or -not (Same-Service $r.local_after.http $r.remote.status)){continue}
        if($r.config.ssh_host -ne $Cfg.ssh_host -or $r.config.remote_dir -ne $Cfg.remote_dir -or $r.config.local_port -ne $Cfg.local_port -or $r.config.web_port -ne $Cfg.web_port){continue}
        $saved=@($r.local_after.listeners)
        if($saved.Count -ne $Listeners.Count){continue}
        $valid=$true
        foreach($l in $Listeners){
            if(-not $l.creation_date -or @($saved | Where-Object {$_.pid -eq $l.pid -and $_.creation_date -eq $l.creation_date -and $_.address -eq $l.address -and $_.name -eq 'ssh.exe'}).Count -ne 1){$valid=$false}
        }
        if($valid){return $true}
    }
    return $false
}
function Write-Dashboard($ServerStatus) {
    $online = ($ServerStatus.data.link.online -eq $true)
    $message = if ($online) {'服务正常，FPGA会话在线；是否有完整图像请看下方统计。'} else {'服务正常，FPGA尚未连接。启动成功不代表通信正常。'}
    $frames = $ServerStatus.data.link.complete_frames
    if ($null -eq $frames) {$frames=0}
    $url = "http://127.0.0.1:$($Cfg.local_port)/"
    $html = @"
<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>M4 前摄运行状态</title>
<style>body{font:18px system-ui;max-width:1000px;margin:40px auto;padding:16px;background:#15202b;color:#eee}a{color:#7dd3fc}iframe{width:100%;height:760px;border:1px solid #555}</style>
<h1>M4-01 前摄运行状态</h1><h2>$message</h2>
<p>状态生成于 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')；这是启动时快照，实时情况查看预览或重新双击通信诊断。</p>
<p>完整帧累计：$frames；前摄上传请求仍为5fps，预览目标15fps不代表前摄收到15fps。</p>
<p><a href="$url" target="_blank">打开实时前摄预览</a>　停止请双击“停止前摄服务”。</p>
<p>关闭此页面或启动窗口后，远端服务继续运行。无画面时双击“检查FPGA通信”，不要把等待首帧当作成功收到视频。</p>
<iframe src="$url" title="前摄预览"></iframe></html>
"@
    $file = Join-Path $ReportDir "startup_$Stamp.html"
    [IO.File]::WriteAllText($file,$html,$Utf8)
    return $file
}

try {
    try { $OpLock=[IO.File]::Open((Join-Path $StateDir 'operation.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
    catch { throw '本工具已有操作正在进行，请等待该窗口完成，未重复创建服务。' }
    $Cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    if ($Cfg.remote_dir -notmatch '^/[A-Za-z0-9_./-]+$' -or $Cfg.remote_tool -notmatch '^[A-Za-z0-9_./-]+$') {throw '远端目录或工具路径格式无效'}
    if ($Cfg.ssh_host -notmatch '^[A-Za-z0-9._:-]+$' -or $Cfg.ssh_user -notmatch '^[A-Za-z0-9_-]+$') {throw 'SSH地址或用户名格式无效'}
    $Ssh = (Get-Command ssh.exe -ErrorAction Stop).Source
    $SshArgs = @('-p',"$($Cfg.ssh_port)",'-o','StrictHostKeyChecking=yes','-o','ConnectTimeout=8','-o','ConnectionAttempts=1','-o','ServerAliveInterval=10','-o','ServerAliveCountMax=3')
    $Target = "$($Cfg.ssh_user)@$($Cfg.ssh_host)"
    $Result.config=$Cfg
    $Result.local_before=[ordered]@{listeners=@(Get-LocalListeners);http=(Get-Http)}
    Say "本地入口：$PSScriptRoot"
    Say "目标：$Target；远端目录：$($Cfg.remote_dir)"
    if ($Action -eq 'Diagnose') {
        Say '诊断只读；不会启动第二份LIVE、不会占用UDP50000、不会添加静态ARP。'
        try { $Result.remote=Invoke-Remote 'diagnose'; $Result.ssh_ok=$true } catch { $Result.ssh_ok=$false; throw }
        if (-not $Result.remote.ok) {throw $Result.remote.message}
        $Result.local_after=[ordered]@{listeners=@(Get-LocalListeners);http=(Get-Http)}
        $same=Same-Service $Result.local_after.http $Result.remote.samples[1].status
        $Result.forward_matches_remote=$same
        Say ('SSH：可连接；远端版本：'+$Result.remote.version)
        Say ('本地转发/HTTP：'+$(if($same){'可访问，session与远端一致'}else{'不可访问或不能证明对应当前服务'}))
        foreach ($line in $Result.remote.conclusions) {Say $line}
        Say ('网卡增量：'+($Result.remote.nic_delta | ConvertTo-Json -Compress))
        Say ('协议增量：'+($Result.remote.link_delta | ConvertTo-Json -Compress))
        Say '端口占用及进程命令行：'
        Say ($Result.remote.sockets.stdout | Out-String)
        $Result.ok=$true
    } elseif ($Action -eq 'Start') {
        $Result.preflight=Invoke-Remote 'preflight'
        if (-not $Result.preflight.ok) {throw $Result.preflight.message}
        if (-not $Result.preflight.business_address_present -or $Result.preflight.carrier -ne 1) {
            foreach($line in $Result.preflight.errors){Say $line}
            if (-not $Result.preflight.business_address_present) {
                throw '现有eth0业务地址缺失；本入口不会修改IP、路由或邻居。请回传启动报告。'
            } else {Say '物理链路未建立或未知；仍可运行服务并打开诊断页面，不视为通信通过。'}
        }
        # Refuse an occupied local port unless it is an SSH listener and already
        # serves the exact remote live session. This unmanaged tunnel is never killed.
        $listeners=@(Get-LocalListeners)
        if($listeners.Count -gt 0) {
            $remoteNow=Invoke-Remote 'diagnose'
            $httpNow=Get-Http
            $matched=Same-Service $httpNow $remoteNow.samples[1].status
            $prior=Previously-VerifiedForward $listeners
            if(@($listeners | Where-Object {$_.name -ne 'ssh.exe'}).Count -gt 0 -or (-not $matched -and -not $prior)) {
                $Result.local_conflict=$listeners
                Say ($listeners | Format-List | Out-String)
                throw "本地$($Cfg.local_port)被其他程序或无法确认的转发占用，未停止任何进程。"
            }
            Say $(if($matched){'已有SSH转发，HTTP会话与当前远端一致，将复用；非本工具创建的转发停止时保留。'}else{'已有SSH转发与此前成功记录的PID/启动时间一致，将在服务启动后再次核对HTTP会话；停止时保留该外部转发。'})
        }
        $Result.remote=Invoke-Remote 'start'
        if(-not $Result.remote.ok){Say ($Result.remote | ConvertTo-Json -Depth 12);throw $Result.remote.message}
        Say $Result.remote.message
        if($listeners.Count -eq 0) {
            $existing=Get-OwnedTunnel
            if($existing){throw '已记录的SSH进程仍存在但转发端口未监听，请先停止或查看其认证窗口'}
            $tunnelArgs=$SshArgs+@('-o','ExitOnForwardFailure=yes','-N','-L',"127.0.0.1:$($Cfg.local_port):127.0.0.1:$($Cfg.web_port)",$Target)
            Say '新开SSH转发窗口；密码登录时请在该窗口输入SSH密码，勿关闭该窗口。'
            $tunnel=Start-Process -FilePath $Ssh -ArgumentList $tunnelArgs -WindowStyle Normal -PassThru
            $creationDeadline=[DateTime]::UtcNow.AddSeconds(3)
            do {
                $p=Get-CimInstance Win32_Process -Filter "ProcessId=$($tunnel.Id)" -ErrorAction SilentlyContinue
                if($p -and $p.CommandLine){break};Start-Sleep -Milliseconds 100
            }while([DateTime]::UtcNow -lt $creationDeadline)
            if(-not $p.CommandLine){throw '无法记录本次SSH命令行身份，请查看SSH窗口；不会猜测结束进程'}
            Save-Json ([ordered]@{pid=$p.ProcessId;command_line=$p.CommandLine;creation_date=[string]$p.CreationDate;config=$Cfg}) (Join-Path $StateDir 'tunnel.json')
        }
        $deadline=[DateTime]::UtcNow.AddSeconds([int]$Cfg.startup_timeout_seconds)
        do {
            $http=Get-Http
            if(Same-Service $http $Result.remote.status){break}
            Start-Sleep -Milliseconds 200
        }while([DateTime]::UtcNow -lt $deadline)
        if(-not (Same-Service $http $Result.remote.status)){throw '等待转发和LIVE状态超时；远端可能仍运行，请查看SSH认证窗口或运行停止/诊断入口。'}
        $Result.local_after=[ordered]@{listeners=@(Get-LocalListeners);http=$http}
        Say '服务：运行；SSH转发及HTTP：正常。'
        Say $(if($http.data.link.online){'FPGA：会话在线'}else{'服务正常，FPGA尚未连接（online=false）'})
        $count=$http.data.link.complete_frames;if($null -eq $count){$count=0}
        Say "完整前摄帧累计：$count；前摄请求5fps，预览目标$($Cfg.preview_fps)fps不代表实际前摄接收率。"
        Say "预览：http://127.0.0.1:$($Cfg.local_port)/"
        Say '关闭启动窗口后远端继续运行；停止请双击“停止前摄服务”。已有的外部转发不会被工具结束。'
        $dashboard=Write-Dashboard $http
        $Result.dashboard=$dashboard
        if(-not $NoBrowser){Start-Process $dashboard}
        $Result.ok=$true
    } else {
        $Result.remote=Invoke-Remote 'stop'
        Say $Result.remote.message
        if(-not $Result.remote.ok){throw $Result.remote.message}
        $owned=Get-OwnedTunnel
        if($owned){
            Stop-Process -Id $owned.ProcessId -ErrorAction Stop
            $record=Join-Path $StateDir 'tunnel.json'
            $saved=Get-Content -LiteralPath $record -Raw | ConvertFrom-Json
            $saved | Add-Member -NotePropertyName stopped_at -NotePropertyValue (Get-Date -Format o) -Force
            Save-Json $saved $record
            Say '已停止本入口创建并核对身份的SSH转发。'
        }
        else {Say '本入口没有运行中的SSH转发；现有外部转发不会被停止，可在其原窗口Ctrl+C。'}
        $Result.local_after=[ordered]@{listeners=@(Get-LocalListeners);http=(Get-Http)}
        $Result.ok=$true
    }
} catch {
    $Result.error=$_.Exception.Message
    Say ('操作未完成：'+$Result.error)
    if($Action -eq 'Diagnose') {Say 'SSH失败时无法判断板端服务/eth0状态；不据此推断FPGA故障。'}
} finally {
    $jsonPath=Join-Path $ReportDir "$($Action.ToLower())_$Stamp.json"
    $textPath=Join-Path $ReportDir "$($Action.ToLower())_$Stamp.txt"
    $Result.summary=@($Trace.ToArray())
    Save-Json $Result $jsonPath
    $details=$Result | ConvertTo-Json -Depth 40
    [IO.File]::WriteAllText($textPath,(($Trace.ToArray() -join "`r`n")+"`r`n`r`n结构化详情：`r`n"+$details),$Utf8)
    if($Action -eq 'Diagnose') {
        Copy-Item -LiteralPath $textPath -Destination (Join-Path $ReportDir 'latest_diagnosis.txt') -Force
        Copy-Item -LiteralPath $jsonPath -Destination (Join-Path $ReportDir 'latest_diagnosis.json') -Force
    }
    Write-Host "文本报告：$textPath"
    Write-Host "JSON报告：$jsonPath"
    if($OpLock){$OpLock.Dispose()}
    if(-not $NoPause){[void](Read-Host '按回车关闭此窗口')}
}
if(-not $Result.ok){exit 1}
