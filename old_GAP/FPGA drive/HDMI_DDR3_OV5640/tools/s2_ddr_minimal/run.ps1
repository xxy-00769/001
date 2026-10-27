param(
    [ValidateSet('control', 'rd_buf')]
    [string]$Case = 'control',
    [string]$OutputParent = 'E:\FPGA drive\tmp\s2_ddr_minimal',
    [string]$ModelSim = 'D:\PDS\Modelsim\win64',
    [string]$PrimitiveLibrary = 'D:\PDS\PDS_2022.2-SP6.1\arch\vendor\pango\verilog\simulation'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$env:GIT_OPTIONAL_LOCKS = '0'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$entry = Split-Path $repo -Parent
$archive = Join-Path $entry '_archive\experiments\road_video_ddr_20261017'
$stamp = (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$run = [IO.Path]::GetFullPath((Join-Path $OutputParent ($stamp + '_' + $Case)))
if (Test-Path -LiteralPath $run) { throw 'Run directory already exists.' }
if ($run.StartsWith((Join-Path $repo 'source') + '\', [StringComparison]::OrdinalIgnoreCase) -or
    $run.StartsWith($archive + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Output directory must not be inside main RTL or the historical archive.'
}
foreach ($tool in @('vlib.exe','vlog.exe','vsim.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $ModelSim $tool))) { throw "Missing simulator tool: $tool" }
}

if ($Case -eq 'control') {
    $top = 'control_tb'
    $sources = @(
        (Join-Path $repo 'source\rtl\wr_cmd_trans.v'),
        (Join-Path $archive 'tests\control_tb.sv')
    )
    $primitiveSources = @()
    $trace = 'vcd file control.vcd; vcd add -r /control_tb/*;'
} else {
    $top = 's2_rd_buf_full_frame_tb'
    $sources = @(
        (Join-Path $repo 'source\rtl\rd_buf.v'),
        (Join-Path $repo 'source\rtl\rd_fram_buf\rd_fram_buf.v'),
        (Join-Path $repo 'source\rtl\rd_fram_buf\rtl\ipml_sdpram_v1_6_rd_fram_buf.v'),
        (Join-Path $PSScriptRoot 'rd_buf_full_frame_tb.sv')
    )
    $primitiveSources = @('GTP_GRS.v','GTP_DRM18K.v' | ForEach-Object { Join-Path $PrimitiveLibrary $_ })
    $trace = 'vcd file rd_buf_control.vcd; vcd add /s2_rd_buf_full_frame_tb/dut/wr_line /s2_rd_buf_full_frame_tb/ddr_rreq /s2_rd_buf_full_frame_tb/ddr_raddr /s2_rd_buf_full_frame_tb/ddr_rdone /s2_rd_buf_full_frame_tb/rd_fsync;'
}
foreach ($path in @($sources) + @($primitiveSources)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing input: $path" }
}
[IO.Directory]::CreateDirectory($run) | Out-Null

function Save-Json($Path, $Value) {
    ConvertTo-Json -InputObject $Value -Depth 12 | Set-Content -LiteralPath $Path -Encoding utf8
}
function Hashes($Paths) {
    @($Paths | Sort-Object -Unique | ForEach-Object {
        $item = Get-Item -LiteralPath $_ -Force
        [pscustomobject]@{
            Path = $item.FullName; Size = $item.Length; MtimeUtc = $item.LastWriteTimeUtc.ToString('o')
            SHA256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        }
    })
}
$protectedPaths = @(
    foreach ($dir in @('source','host','tests','tools','bitstreams')) {
        Get-ChildItem -LiteralPath (Join-Path $repo $dir) -File -Force -Recurse | Select-Object -ExpandProperty FullName
    }
    foreach ($name in @('flow.tcl','build.bat','HDMI_DDR3_OV5640.pds','hdmi_ddr_ov5640_top.fdc','README.md','.gitignore','.git\index')) {
        Join-Path $repo $name
    }
)
$protectedBefore = Hashes $protectedPaths
$inputBefore = Hashes (@($sources) + @($primitiveSources) + @($PSCommandPath))
Save-Json (Join-Path $run 'protected_before.json') $protectedBefore
Save-Json (Join-Path $run 'inputs_before.json') $inputBefore
foreach ($kind in @('head','status','diff')) {
    $gitArgs = switch ($kind) {
        'head' { @('rev-parse','HEAD') }
        'status' { @('status','--short','--branch','--untracked-files=all') }
        'diff' { @('diff','--binary','--no-ext-diff') }
    }
    $output = @(& git --no-optional-locks -c core.quotePath=false -C $repo @gitArgs)
    if ($LASTEXITCODE -ne 0) { throw "Git read failed: $kind" }
    $output | Set-Content -LiteralPath (Join-Path $run "git_before_$kind.txt") -Encoding utf8
}
$commands = [Collections.Generic.List[object]]::new()
function Invoke-Recorded([string]$Tool, [string[]]$Arguments, [string]$Log) {
    $start = [DateTime]::UtcNow
    & $Tool @Arguments *> (Join-Path $run $Log)
    $exit = $LASTEXITCODE
    $commands.Add([pscustomobject]@{
        Tool = $Tool; Arguments = $Arguments; WorkingDirectory = $run
        StartedUtc = $start.ToString('o'); FinishedUtc = [DateTime]::UtcNow.ToString('o')
        ExitCode = $exit; Log = $Log
    })
    Save-Json (Join-Path $run 'commands.json') @($commands.ToArray())
    if ($exit -ne 0) { throw "$Tool exited $exit; see $run\$Log" }
}

$result = [ordered]@{
    Case = $Case; RunDirectory = $run; Sources = $sources
    TestLevel = 'RTL simulation'; CurrentMainRTL = $true; HistoricalCandidateCompiled = $false
    FullDDRControllerPHY = $false; BoardTest = $false; SynthesisOrBitstream = $false
    ToolExecutionSucceeded = $false; Verdict = 'BLOCKED'; Error = $null
}
Push-Location $run
try {
    Invoke-Recorded (Join-Path $ModelSim 'vlog.exe') @('-version') 'vlog_version.log'
    Invoke-Recorded (Join-Path $ModelSim 'vsim.exe') @('-version') 'vsim_version.log'
    Invoke-Recorded (Join-Path $ModelSim 'vlib.exe') @('work') 'library.log'
    $compileArgs = @('-sv','-work','work') + $sources
    if ($primitiveSources.Count -gt 0) { $compileArgs += @('-y', $PrimitiveLibrary, '+libext+.v') }
    Invoke-Recorded (Join-Path $ModelSim 'vlog.exe') $compileArgs 'compile.log'
    $do = "onerror {quit -code 2}; $trace run -all; quit -code 0"
    Invoke-Recorded (Join-Path $ModelSim 'vsim.exe') @(
        '-c','-novopt','-t','1ps','-suppress','12110','-lib','work',$top,
        '-do',$do,'-l','simulation.log'
    ) 'console.log'
    $text = Get-Content -LiteralPath (Join-Path $run 'simulation.log') -Raw
    if ($text -match '\*\* (Error|Fatal):') { throw 'Simulator reported Error/Fatal; see simulation.log.' }
    if ($Case -eq 'control') {
        $match = [regex]::Match($text, 'CONTROL_RESULT premature=(\d+) completion_cycles=(\d+) accepted_returns=(\d+)')
        if (-not $match.Success) { throw 'Missing control result; not a completed simulation test.' }
        $result.PrematureCompletionCycles = [int]$match.Groups[1].Value
        $result.CompletionCycles = [int]$match.Groups[2].Value
        $result.AcceptedReturns = [int]$match.Groups[3].Value
        $result.Verdict = if ($result.PrematureCompletionCycles -eq 0 -and
            $result.CompletionCycles -eq 1 -and $result.AcceptedReturns -eq 80) { 'PASS' } else { 'FAIL' }
    } else {
        $match = [regex]::Match($text, 'RD_BUF_RESULT requests=(\d+) completions=(\d+) beats=(\d+) pixels=(\d+) errors=(\d+) last_row_errors=(\d+) missing_rows=(\d+) address_errors=(\d+) line_length_errors=(\d+)')
        if (-not $match.Success) { throw 'Missing rd_buf result; not a completed simulation test.' }
        $keys = @('Requests','Completions','ReturnedBeats','Pixels','PixelErrors','LastRowErrors','MissingRows','AddressErrors','LineLengthErrors')
        for ($i=0; $i -lt $keys.Count; $i++) { $result[$keys[$i]] = [int]$match.Groups[$i+1].Value }
        $result.Verdict = if ($result.Requests -eq 720 -and $result.Completions -eq 720 -and
            $result.ReturnedBeats -eq 57600 -and $result.Pixels -eq 921600 -and
            $result.PixelErrors -eq 0 -and $result.MissingRows -eq 0 -and
            $result.AddressErrors -eq 0 -and $result.LineLengthErrors -eq 0) { 'PASS' } else { 'FAIL' }
    }
    $result.ToolExecutionSucceeded = $true
} catch {
    $result.Error = $_.Exception.Message
} finally {
    Pop-Location
    $protectedAfter = Hashes $protectedPaths
    $inputAfter = Hashes (@($sources) + @($primitiveSources) + @($PSCommandPath))
    Save-Json (Join-Path $run 'protected_after.json') $protectedAfter
    Save-Json (Join-Path $run 'inputs_after.json') $inputAfter
    $result.ProtectedFilesUnchanged = @(Compare-Object $protectedBefore $protectedAfter -Property Path,SHA256).Count -eq 0
    $result.InputsUnchanged = @(Compare-Object $inputBefore $inputAfter -Property Path,SHA256).Count -eq 0
    if (-not $result.ProtectedFilesUnchanged -or -not $result.InputsUnchanged) {
        $result.Verdict = 'INVALID_INPUT_CHANGED'
    }
    Save-Json (Join-Path $run 'result.json') $result
    $evidence = @(Get-ChildItem -LiteralPath $run -File | Where-Object Name -ne 'evidence_manifest.json' |
        ForEach-Object { [pscustomobject]@{
            Path = $_.FullName; Size = $_.Length
            SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        } })
    Save-Json (Join-Path $run 'evidence_manifest.json') $evidence
}
$result | ConvertTo-Json -Depth 8
if (-not $result.ToolExecutionSucceeded -or $result.Verdict -eq 'INVALID_INPUT_CHANGED') { exit 2 }
if ($result.Verdict -eq 'FAIL') { exit 1 }
