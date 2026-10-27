param([switch]$NoPause)
$ErrorActionPreference='Stop'
try {
    [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
    $OutputEncoding=[Console]::OutputEncoding
    $c=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if($c.remote_dir -notmatch '^/[A-Za-z0-9_./-]+$'){throw '项目目录格式无效'}
    $backup=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'state/rxfix_backup.txt') -Raw
    $backup=Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) $backup.Trim()
    if(-not (Test-Path -LiteralPath (Join-Path $backup 'launcher.ps1'))){throw "本地旧版本不存在：$backup"}
    Write-Host '回退将正常停止本项目服务及本入口的SSH转发，恢复记录的临时rmem_max和旧操作工具。'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'launcher.ps1') -Action Stop -NoPause
    if($LASTEXITCODE -ne 0){throw '服务未能安全停止，停止回退'}
    $target='{0}@{1}' -f $c.ssh_user,$c.ssh_host
    & ssh.exe -p $c.ssh_port -o StrictHostKeyChecking=yes -t $target "cd '$($c.remote_dir)' && .venv/bin/python operator_v1/buffer_control.py restore --root '$($c.remote_dir)'"
    if($LASTEXITCODE -ne 0){throw '内核值恢复失败或被其他操作改变；未覆盖其他设置，请看终端提示'}
    & ssh.exe -p $c.ssh_port -o StrictHostKeyChecking=yes $target "cd '$($c.remote_dir)' && tar -xzf operator_v1/rxfix_backup_20261023/before.tgz main.py link.py operator_v1/ops_manager.py"
    if($LASTEXITCODE -ne 0){throw '远端操作工具恢复失败，服务保持停止'}
    foreach($file in @('launcher.ps1','ops_manager.py','collect_freeze.py','collect_freeze.ps1')) {
        Copy-Item -LiteralPath (Join-Path $backup $file) -Destination (Join-Path $PSScriptRoot $file) -Force
    }
    & tar.exe -xzf (Join-Path $backup 'before.tgz') -C (Split-Path $PSScriptRoot -Parent) main.py link.py
    if($LASTEXITCODE -ne 0){throw '本地主程序回退未完成，远端服务保持停止'}
    Write-Host '回退完成，服务保持停止。需要运行旧版时双击“启动前摄预览”；旧版小缓冲丢包问题将重新存在。'
    Write-Host 'SSH地址和Wi-Fi/业务网络配置均未覆盖，没有永久sysctl或开机服务。'
} catch { Write-Host ('回退未完成：'+$_.Exception.Message) -ForegroundColor Red }
finally { if(!$NoPause){Read-Host '按回车关闭窗口' | Out-Null} }
