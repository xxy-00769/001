param([ValidateSet('Start','Stop')][string]$Action='Start',[switch]$NoPause,[switch]$NoBrowser)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);$OutputEncoding=[Console]::OutputEncoding
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff';$state=Join-Path $PSScriptRoot 'state';$reports=Join-Path $PSScriptRoot 'reports'
New-Item -ItemType Directory -Force $state,$reports | Out-Null
$result=[ordered]@{action=$Action;version='M4-04-r1';ok=$false};$lock=$null
function SaveJson($o,$p){[IO.File]::WriteAllText($p,($o|ConvertTo-Json -Depth 40),[Text.UTF8Encoding]::new($false))}
function Http {try{return (Invoke-RestMethod "http://127.0.0.1:$($cfg.local_port)/status.json?t=$([DateTimeOffset]::Now.ToUnixTimeMilliseconds())" -TimeoutSec 3)}catch{return $null}}
function TunnelRecord($path){
 if(!(Test-Path -LiteralPath $path)){return $null}
 $r=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
 $p=Get-CimInstance Win32_Process -Filter "ProcessId=$($r.pid)" -ErrorAction SilentlyContinue
 if($p -and $p.Name -eq 'ssh.exe' -and $p.CommandLine -eq $r.command_line -and [string]$p.CreationDate -eq $r.creation_date){return $p}
 return $null
}
try {
 $lock=[IO.File]::Open((Join-Path $state 'operation.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 $cfg=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if($cfg.remote_dir -notmatch '^/[A-Za-z0-9_./-]+$' -or $cfg.ssh_host -notmatch '^[A-Za-z0-9._:-]+$' -or $cfg.ssh_user -notmatch '^[A-Za-z0-9_-]+$'){throw '集中配置中的SSH地址或路径无效'}
 $ssh=(Get-Command ssh.exe -ErrorAction Stop).Source;$target="$($cfg.ssh_user)@$($cfg.ssh_host)"
 $sshArgs=@('-p',"$($cfg.ssh_port)",'-o','StrictHostKeyChecking=yes','-o','ConnectTimeout=8','-o','ServerAliveInterval=10','-o','ServerAliveCountMax=3')
 $listeners=@(Get-NetTCPConnection -LocalPort $cfg.local_port -State Listen -ErrorAction SilentlyContinue)
 if($Action -eq 'Start' -and $listeners.Count){
  $known=@((TunnelRecord (Join-Path $state 'tunnel.json')),(TunnelRecord (Join-Path $state 'demo_tunnel.json'))) | Where-Object {$_}
  foreach($listener in $listeners){if(@($known|Where-Object {$_.ProcessId -eq $listener.OwningProcess}).Count -eq 0){
   $owner=Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)"
   throw "本地$($cfg.local_port)被其他/未确认程序占用：PID=$($owner.ProcessId)，$($owner.CommandLine)。未结束它。"
  }}
  foreach($own in $known){
   if($own.CommandLine -notmatch ([regex]::Escape($target)+'(?:\s|$)')){
    Stop-Process -Id $own.ProcessId
    Write-Host '已关闭身份核实的旧地址项目转发，按集中配置重建。'
   }
  }
  $listeners=@(Get-NetTCPConnection -LocalPort $cfg.local_port -State Listen -ErrorAction SilentlyContinue)
  if($listeners.Count){Write-Host '复用已有本项目SSH转发。'}
 }
 if(!$cfg.demo_ops){$cfg|Add-Member demo_ops 'm404/demo_ops.py'}
 if($cfg.demo_ops -notin @('m403/demo_ops.py','m404/demo_ops.py','m405/demo_ops.py','m405r2/demo_ops.py','m406/demo_ops.py')){throw '录像版本入口无效，请使用M4-03/M4-04回退或M4-05切回入口'}
 $result.version=if($cfg.demo_ops -eq 'm403/demo_ops.py'){'M4-03-demo-r1'}elseif($cfg.demo_ops -eq 'm405/demo_ops.py'){'M4-05-r1'}elseif($cfg.demo_ops -eq 'm405r2/demo_ops.py'){'M4-05-r2'}elseif($cfg.demo_ops -eq 'm406/demo_ops.py'){'M4-06-r1'}else{'M4-04-r1'}
 $b64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($cfg|ConvertTo-Json -Compress)))
 $reply=Join-Path $state "demo_reply_$stamp.json"
 Write-Host "本地录像／模拟车辆：$target；需要时请在窗口输入SSH密码（不保存）。"
 & $ssh @sshArgs $target "cd '$($cfg.remote_dir)' && .venv/bin/python $($cfg.demo_ops) $($Action.ToLower()) --config $b64" > $reply
 if($LASTEXITCODE -ne 0){throw 'SSH连接/认证/主机校验或远端入口失败，请查看上方提示'}
 $remote=Get-Content -LiteralPath $reply -Raw -Encoding UTF8|ConvertFrom-Json;$result.remote=$remote
 Write-Host $remote.message
 if(!$remote.ok){throw ($remote|ConvertTo-Json -Depth 8)}
 if($Action -eq 'Start'){
  if(!$listeners.Count){
   $args=$sshArgs+@('-o','ExitOnForwardFailure=yes','-N','-L',"127.0.0.1:$($cfg.local_port):127.0.0.1:$($cfg.web_port)",$target)
   $child=Start-Process $ssh -ArgumentList $args -PassThru -WindowStyle Hidden
   $deadline=[DateTime]::UtcNow.AddSeconds(4)
   do{$owner=Get-CimInstance Win32_Process -Filter "ProcessId=$($child.Id)" -ErrorAction SilentlyContinue;if($owner.CommandLine){break};Start-Sleep -Milliseconds 100}while([DateTime]::UtcNow -lt $deadline)
   if(!$owner.CommandLine){throw '转发进程身份未就绪，未猜测接管'}
   SaveJson @{pid=$owner.ProcessId;command_line=$owner.CommandLine;creation_date=[string]$owner.CreationDate} (Join-Path $state 'demo_tunnel.json')
  }
  $deadline=[DateTime]::UtcNow.AddSeconds(45)
  do{$http=Http;if($http -and $http.instance -eq $remote.status.data.instance){break};Start-Sleep -Milliseconds 200}while([DateTime]::UtcNow -lt $deadline)
  if(!$http -or $http.instance -ne $remote.status.data.instance){throw 'HTTP/SSH转发验证超时；远端可能继续运行，使用停止录像演示入口处理'}
  Write-Host "录像演示已运行，PID=$($remote.process.pid)，HTTP/SSH已核对。无业务UDP，无需FPGA。"
  Write-Host "打开 http://127.0.0.1:$($cfg.local_port)/ ；可选四视频、播放/暂停、跳转，点击十字路口或道路变道。"
  Write-Host '关闭本窗口后远端继续运行；双击“停止智驾录像演示”正常停止。原LIVE版本未覆盖。'
  if($cfg.demo_ops -eq 'm406/demo_ops.py'){Write-Host 'M4-06-r1为受限交通灯基线：已有真实红/绿灯画面，远灯/箭头/行人灯与控制归属未完成。请点击网页“夜间红灯”或“夜间绿灯”观察；不自动放行。'}
  if(!$NoBrowser){Start-Process "http://127.0.0.1:$($cfg.local_port)/"}
 }else{
  $own=TunnelRecord (Join-Path $state 'demo_tunnel.json')
  if($own){Stop-Process -Id $own.ProcessId;Write-Host '已清理本录像入口创建的SSH转发。'}else{Write-Host '保留其他入口创建的已有SSH转发，不影响其他SSH任务。'}
 }
 $result.ok=$true
}catch{$result.error=$_.Exception.Message;Write-Host ('未完成：'+$result.error) -ForegroundColor Red}
finally{
 if($lock){$lock.Dispose()};$path=Join-Path $reports "demo_$($Action.ToLower())_$stamp.json";SaveJson $result $path;Write-Host "操作报告：$path"
 if(!$NoPause){Read-Host '按回车关闭'|Out-Null}
}
if(!$result.ok){exit 1}
