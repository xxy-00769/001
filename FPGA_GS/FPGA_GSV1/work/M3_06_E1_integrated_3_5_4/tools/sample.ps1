param([switch]$NoPause)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$exitCode = 1
$report = $null

function Write-SampleLog([string]$Message) {
    Write-Host $Message
    if ($script:report) {
        Add-Content -LiteralPath $script:report -Value $Message -Encoding UTF8
    }
}

function Invoke-SampleCommand([string]$Executable, [string[]]$CommandArgs, [string]$Stage) {
    Write-SampleLog "--- $Stage ---"
    # Stream characters instead of PS's line-buffered native pipeline: sudo's
    # password prompt has no newline. Never redirect/capture stdin/passwords.
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $quoted = foreach ($argument in $CommandArgs) {
        '"' + [regex]::Replace([regex]::Replace($argument, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
    }
    $start.Arguments = $quoted -join ' '
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $start.StandardErrorEncoding = $start.StandardOutputEncoding
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    $stderrText = New-Object System.Text.StringBuilder
    try {
        [void]$process.Start()
        $outBuffer = New-Object char[] 1024
        $errBuffer = New-Object char[] 1024
        $outTask = $process.StandardOutput.ReadAsync($outBuffer, 0, $outBuffer.Length)
        $errTask = $process.StandardError.ReadAsync($errBuffer, 0, $errBuffer.Length)
        while ($null -ne $outTask -or $null -ne $errTask) {
            foreach ($stream in @('out', 'err')) {
                $task = if ($stream -eq 'out') { $outTask } else { $errTask }
                if ($null -eq $task -or -not $task.IsCompleted) { continue }
                $count = $task.GetAwaiter().GetResult()
                if ($count -gt 0) {
                    $buffer = if ($stream -eq 'out') { $outBuffer } else { $errBuffer }
                    $text = -join $buffer[0..($count - 1)]
                    [Console]::Write($text)
                    if ($stream -eq 'out') {
                        Add-Content -LiteralPath $script:report -Value $text -NoNewline -Encoding UTF8
                    } else {
                        # Do not interleave SSH closure text into the JSON body.
                        [void]$stderrText.Append($text)
                    }
                }
                if ($stream -eq 'out') {
                    $outTask = if ($count -gt 0) { $process.StandardOutput.ReadAsync($outBuffer, 0, $outBuffer.Length) } else { $null }
                } else {
                    $errTask = if ($count -gt 0) { $process.StandardError.ReadAsync($errBuffer, 0, $errBuffer.Length) } else { $null }
                }
            }
            $pending = @($outTask, $errTask) | Where-Object { $null -ne $_ }
            if ($pending.Count) { [void][System.Threading.Tasks.Task]::WaitAny([System.Threading.Tasks.Task[]]$pending, 50) }
        }
        $process.WaitForExit()
        $nativeCode = $process.ExitCode
    } finally {
        if ($stderrText.Length) {
            Add-Content -LiteralPath $script:report -Value ("`r`n[stderr]`r`n" + $stderrText.ToString()) -Encoding UTF8
        }
        $process.Dispose()
    }
    Write-SampleLog ''
    Write-SampleLog "$Stage exit_code=$nativeCode"
    if ($nativeCode -ne 0) { throw "$Stage 失败，退出码 $nativeCode" }
}

try {
    $dir = Join-Path $PSScriptRoot 'reports'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $report = Join-Path $dir ('M364_sample_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '.txt')
    Write-SampleLog '3.5.4完整工程检查：上传独立脚本，通过SSH/sudo只读采样10秒。'
    Write-SampleLog '需要时输入现有SSH密码及sudo密码；不保存密码。'
    Write-SampleLog '读取自动ARP、心跳、完整前摄帧/fps和硬件CRC；不更改网络或服务，不发送独立探测包。'

    $cfg = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Raw | ConvertFrom-Json
    $port = 0
    if ($cfg.ssh_host -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]*$' -or
        $cfg.ssh_user -notmatch '^[A-Za-z0-9_][A-Za-z0-9_-]*$' -or
        -not [int]::TryParse([string]$cfg.ssh_port, [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
        throw 'config.json中的SSH主机、用户或端口无效'
    }
    $ssh = (Get-Command ssh.exe -CommandType Application -ErrorAction Stop).Source
    $scp = (Get-Command scp.exe -CommandType Application -ErrorAction Stop).Source
    $localScript = (Get-Item -LiteralPath (Join-Path $PSScriptRoot 'sample_net2.py')).FullName
    $peer = "$($cfg.ssh_user)@$($cfg.ssh_host)"
    # Relative to the SSH user's home; no embedded Python or nested quotes.
    $remoteScript = './fpga_gsv1_m364_tools/sample_net2.py'
    $options = @('-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=8')
    Write-SampleLog "SSH: $peer port=$port; remote_script=$remoteScript"
    Invoke-SampleCommand $ssh (@('-p', "$port") + $options + @($peer, 'mkdir -p ./fpga_gsv1_m364_tools')) '创建用户工具目录'
    $scpHost = [string]$cfg.ssh_host
    if ($scpHost.Contains(':')) { $scpHost = "[$scpHost]" }
    $destination = "$($cfg.ssh_user)@${scpHost}:fpga_gsv1_m364_tools/sample_net2.py"
    Invoke-SampleCommand $scp (@('-P', "$port") + $options + @($localScript, $destination)) 'SCP上传脚本'
    if ($cfg.interface -notmatch '^[A-Za-z0-9_.:-]+$' -or
        $cfg.fpga_ip -notmatch '^192[.]168[.]60[.]2$' -or
        $cfg.fpga_mac -notmatch '^(?i)02:00:47:53:56:32$' -or
        [int]$cfg.web_port -lt 1 -or [int]$cfg.web_port -gt 65535) { throw '采样接口或业务端点配置无效' }
    $remoteCommand = "sudo python3 $remoteScript --interface $($cfg.interface) --seconds 10 --web-port $([int]$cfg.web_port) --fpga-ip $($cfg.fpga_ip) --fpga-mac $($cfg.fpga_mac)"
    Invoke-SampleCommand $ssh (@('-t', '-p', "$port") + $options + @($peer, $remoteCommand)) 'SSH sudo采样' 

    $raw = Get-Content -LiteralPath $report -Raw -Encoding UTF8
    $begin = '=== M364_SAMPLE_JSON_BEGIN ==='
    $end = '=== M364_SAMPLE_JSON_END ==='
    if ([regex]::Matches($raw, [regex]::Escape($begin)).Count -ne 1 -or
        [regex]::Matches($raw, [regex]::Escape($end)).Count -ne 1) {
        throw '缺少唯一且完整的M364_SAMPLE_JSON_BEGIN/END结果'
    }
    $match = [regex]::Match($raw, '(?s)' + [regex]::Escape($begin) + '\s*(.*?)\s*' + [regex]::Escape($end))
    if (-not $match.Success) { throw '采样结果标记顺序错误' }
    $result = $match.Groups[1].Value | ConvertFrom-Json -ErrorAction Stop
    foreach ($field in @('version','window_seconds','checks','pass_all','hardware_delta','protocol_delta','front_receive_fps','samples')) {
        if ($null -eq $result.PSObject.Properties[$field]) { throw "采样结果缺少字段：$field" }
    }
    if ($result.version -notlike 'M3-06 3.5.4*') { throw '采样版本不符' }
    $jsonPath = [IO.Path]::ChangeExtension($report, '.json')
    [IO.File]::WriteAllText($jsonPath, ($result | ConvertTo-Json -Depth 40), (New-Object Text.UTF8Encoding($false)))
    function Known($Value) { if ($null -eq $Value) { return '未知' }; return [string]$Value }
    Write-SampleLog ('自动ARP：' + (Known $result.checks.automatic_arp))
    Write-SampleLog ('心跳在线：' + (Known $result.checks.online) + '；同窗心跳收到：' + (Known $result.checks.heartbeat_received))
    Write-SampleLog ('同窗完整前摄帧数：' + (Known $result.protocol_delta.complete_frames) + '；实际fps：' + (Known $result.front_receive_fps))
    Write-SampleLog ('主机硬件CRC增量：' + (Known $result.hardware_delta.mmc_rx_crc_error))
    Write-SampleLog ('全部闭环条件满足：' + $result.pass_all)
    Write-SampleLog '采样已完成：已获得完整JSON结果。硬件是否通过请以结果字段为准。'
    $exitCode = 0
} catch {
    Write-SampleLog ('采样未完成：' + $_.Exception.Message)
    Write-SampleLog '本次入口失败不能作为硬件实验结论。请回传本报告。'
} finally {
    if ($report) { Write-Host "采样输出：$report" }
    if (-not $NoPause) { [void](Read-Host '按回车关闭') }
}
exit $exitCode
