param([switch]$NoPause)
$ErrorActionPreference='Stop'
try {
    [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
    $OutputEncoding=[Console]::OutputEncoding
    $cfg=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $backup=(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'state/m402_backup.txt') -Raw).Trim()
    $sourceRoot=Split-Path $PSScriptRoot -Parent
    $resolvedBackup=[IO.Path]::GetFullPath($backup)
    if(-not $resolvedBackup.StartsWith(($PSScriptRoot+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw '回退目录不属于本项目oneclick，拒绝操作'}
    foreach($name in @('main.py','link.py','preview.html','launcher.ps1','ops_manager.py','front15_release.json')){
        if(-not (Test-Path -LiteralPath (Join-Path $resolvedBackup $name))){throw ('缺少回退文件：'+$name)}
    }
    if($cfg.remote_dir -notmatch '^/[A-Za-z0-9_./-]+$'){throw '远端路径格式无效'}
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'launcher.ps1') -Action Stop -NoPause
    if($LASTEXITCODE -ne 0){throw '未能安全停止本项目，取消回退'}
    $target='{0}@{1}' -f $cfg.ssh_user,$cfg.ssh_host
    & ssh.exe -p $cfg.ssh_port -o StrictHostKeyChecking=yes $target "cd '$($cfg.remote_dir)' && .venv/bin/python operator_v1/rollback_m402.py"
    if($LASTEXITCODE -ne 0){throw '远端恢复失败，未覆盖本地文件，请查看原因'}
    foreach($name in @('main.py','link.py','preview.html','front15_release.json')){Copy-Item -LiteralPath (Join-Path $resolvedBackup $name) -Destination (Join-Path $sourceRoot $name) -Force}
    foreach($name in @('launcher.ps1','ops_manager.py')){Copy-Item -LiteralPath (Join-Path $resolvedBackup $name) -Destination (Join-Path $PSScriptRoot $name) -Force}
    $releasePath=Join-Path $sourceRoot 'm402_release.json'
    if(Test-Path -LiteralPath $releasePath){
        $release=Get-Content -LiteralPath $releasePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if($release.version -eq 'M4-02-r1'){Remove-Item -LiteralPath $releasePath}
    }
    Write-Host '已回退front15-r1，当前服务停止。双击“启动前摄预览”恢复运行；集中fps配置和8MiB缓冲均保留。'
} catch {Write-Host ('回退未完成：'+$_.Exception.Message) -ForegroundColor Red;exit 1}
finally {if(!$NoPause){Read-Host '按回车关闭窗口' | Out-Null}}
