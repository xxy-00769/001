param([ValidateRange(0,30)][int]$Fps=15,[switch]$NoPause,[switch]$NoBrowser)
$ErrorActionPreference='Stop'
try {
    [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
    $OutputEncoding=[Console]::OutputEncoding
    $configPath=Join-Path $PSScriptRoot 'config.json'
    $cfg=Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if($cfg.front_fps -ne $Fps){
        Write-Host "先按旧配置核对PID并正常停止，再切换前摄上传请求为${Fps}fps；保持8MiB缓冲修复。"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'launcher.ps1') -Action Stop -NoPause
        if($LASTEXITCODE -ne 0){throw '旧服务未能安全停止，配置未改变'}
        $cfg | Add-Member -NotePropertyName front_fps -NotePropertyValue $Fps -Force
        [IO.File]::WriteAllText($configPath,($cfg | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
    }
    $argsList=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'launcher.ps1'),'-Action','Start','-NoPause')
    if($NoBrowser){$argsList+='-NoBrowser'}
    & powershell.exe @argsList
    if($LASTEXITCODE -ne 0){throw '启动未完成，请查看上述原因和报告；未结束其他进程'}
} catch {Write-Host ('帧率切换未完成：'+$_.Exception.Message) -ForegroundColor Red;exit 1}
finally {if(!$NoPause){Read-Host '按回车关闭窗口' | Out-Null}}
