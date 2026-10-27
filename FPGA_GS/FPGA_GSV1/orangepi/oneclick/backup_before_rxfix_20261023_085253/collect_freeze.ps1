param([string]$ReportDirectory = '', [switch]$NoPause)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
function ShellQuote([string]$Value) {
    if ($Value.Contains("'")) { throw '远端路径含单引号，请使用普通项目路径。' }
    return "'$Value'"
}
try {
    $config = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    if (!$ReportDirectory) { $ReportDirectory = Join-Path $PSScriptRoot "reports/freeze_$stamp" }
    $null = New-Item -ItemType Directory -Force -Path $ReportDirectory
    $ReportDirectory = (Resolve-Path -LiteralPath $ReportDirectory).Path
    $target = '{0}@{1}' -f $config.ssh_user, $config.ssh_host
    $remote = $config.remote_dir + '/operator_v1/freeze_diagnostics/' + $stamp
    $sshArgs = @('-p', [string]$config.ssh_port, '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=10')
    $scpArgs = @('-P', [string]$config.ssh_port, '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=10')
    Get-Command ssh, scp -ErrorAction Stop | Out-Null
    Write-Host '只读冻结诊断：不会启动、停止或重启前摄服务，也不更改网络或系统参数。'
    Write-Host '如SSH要求认证，请在此窗口输入；密码不会写入报告。'
    & ssh @sshArgs $target ('mkdir -p -- ' + (ShellQuote $remote))
    if ($LASTEXITCODE -ne 0) { throw 'SSH连接或建立独立诊断目录失败。' }
    & scp @scpArgs (Join-Path $PSScriptRoot 'collect_freeze.py') (Join-Path $PSScriptRoot 'config.json') "${target}:${remote}/"
    if ($LASTEXITCODE -ne 0) { throw '诊断脚本传输失败。' }
    $command = 'python3 ' + (ShellQuote ($remote + '/collect_freeze.py')) + ' --config ' + (ShellQuote ($remote + '/config.json')) + ' --output ' + (ShellQuote ($remote + '/evidence')) + ' --seconds 30'
    Write-Host '先保存日志和状态，再采集同一30秒窗口，请保留窗口。'
    $result = & ssh @sshArgs $target $command 2>&1
    $code = $LASTEXITCODE
    $result | Out-File -LiteralPath (Join-Path $ReportDirectory 'collector.console.txt') -Encoding utf8
    # Even a partial collection is valuable; copy it before reporting an error.
    & scp @scpArgs -r "${target}:${remote}/evidence/." $ReportDirectory
    $copyCode = $LASTEXITCODE
    if ($code -ne 0 -or $copyCode -ne 0) { throw "采样或回传未完整成功（ssh=$code, scp=$copyCode），已有证据保留在 $ReportDirectory；远端 $remote" }
    $startup = Join-Path $PSScriptRoot 'reports/start_20261022_191505_203.json'
    if (Test-Path -LiteralPath $startup) { Copy-Item -LiteralPath $startup -Destination $ReportDirectory -Force }
    Get-Content -LiteralPath (Join-Path $ReportDirectory 'window.txt') -Encoding UTF8 | Write-Host
    Write-Host "`n报告已保存：$ReportDirectory"
    Write-Host '请回传window.json、metadata.json、samples.jsonl及日志；不会自动启动第二份通信客户端。'
} catch {
    Write-Host ('诊断错误：' + $_.Exception.Message) -ForegroundColor Red
    if ($ReportDirectory -and (Test-Path -LiteralPath $ReportDirectory)) {
        @{ ok=$false; error=$_.Exception.Message; time=(Get-Date -Format o) } | ConvertTo-Json | Out-File -LiteralPath (Join-Path $ReportDirectory 'collection_error.json') -Encoding utf8
    }
} finally {
    if (!$NoPause) { Read-Host '按回车关闭窗口' | Out-Null }
}
