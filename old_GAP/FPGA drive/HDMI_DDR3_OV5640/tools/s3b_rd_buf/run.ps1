param(
    [string]$OutputParent = 'E:\FPGA drive\tmp\s3b_rd_buf',
    [string]$ModelSim = 'D:\PDS\Modelsim\win64',
    [string]$PrimitiveLibrary = 'D:\PDS\PDS_2022.2-SP6.1\arch\vendor\pango\verilog\simulation'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$stamp = (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$run = [IO.Path]::GetFullPath((Join-Path $OutputParent $stamp))
$allowedParent = [IO.Path]::GetFullPath((Join-Path (Split-Path $repo -Parent) 'tmp'))
if (-not $run.StartsWith($allowedParent + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Regression outputs must remain under the workspace tmp directory.'
}
if (Test-Path -LiteralPath $run) { throw 'Output directory already exists.' }
$sources = @(
    (Join-Path $repo 'source\rtl\rd_buf.v'),
    (Join-Path $repo 'source\rtl\rd_fram_buf\rd_fram_buf.v'),
    (Join-Path $repo 'source\rtl\rd_fram_buf\rtl\ipml_sdpram_v1_6_rd_fram_buf.v'),
    (Join-Path $PSScriptRoot 'regression_tb.sv')
)
$inputs = @($sources) + @($PSCommandPath) + @(
    (Join-Path $PrimitiveLibrary 'GTP_GRS.v'),
    (Join-Path $PrimitiveLibrary 'GTP_DRM18K.v')
)
foreach ($path in $inputs) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing input: $path" }
}
foreach ($name in @('vlib.exe','vlog.exe','vsim.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $ModelSim $name))) { throw "Missing tool: $name" }
}
function Hashes {
    @($inputs | ForEach-Object {
        $item = Get-Item -LiteralPath $_
        [pscustomobject]@{
            Path = $item.FullName; Size = $item.Length
            SHA256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash
        }
    })
}
function Save-Json($Name, $Value) {
    ConvertTo-Json -InputObject $Value -Depth 8 |
        Set-Content -LiteralPath (Join-Path $run $Name) -Encoding utf8
}
[IO.Directory]::CreateDirectory($run) | Out-Null
$before = Hashes
Save-Json 'inputs_before.json' $before
$commands = [Collections.Generic.List[object]]::new()
$result = [ordered]@{
    Stage = 'S3b'; TestLevel = 'RTL simulation'; RunDirectory = $run
    FullDDRControllerPHY = $false; Synthesis = $false; BoardTest = $false
    Verdict = 'ERROR'; Error = $null
}
function Invoke-Tool([string]$Name, [string[]]$Arguments, [string]$Log) {
    $start = [DateTime]::UtcNow
    & (Join-Path $ModelSim $Name) @Arguments *> (Join-Path $run $Log)
    $code = $LASTEXITCODE
    $commands.Add([pscustomobject]@{
        Tool = (Join-Path $ModelSim $Name); Arguments = $Arguments; WorkingDirectory = $run
        StartedUtc = $start.ToString('o'); FinishedUtc = [DateTime]::UtcNow.ToString('o')
        ExitCode = $code; Log = $Log
    })
    if ($code -ne 0) { throw "$Name exited $code; see $Log" }
}
Push-Location $run
try {
    Invoke-Tool 'vlog.exe' @('-version') 'version.log'
    Invoke-Tool 'vlib.exe' @('work') 'library.log'
    Invoke-Tool 'vlog.exe' (@('-sv','-work','work') + $sources +
        @('-y',$PrimitiveLibrary,'+libext+.v')) 'compile.log'
    Invoke-Tool 'vsim.exe' @('-c','-novopt','-t','1ps','-suppress','12110',
        '-lib','work','s3b_rd_buf_tb','-do',
        'onerror {quit -code 2}; vcd file control.vcd; vcd add /s3b_rd_buf_tb/dut/wr_line /s3b_rd_buf_tb/ddr_rreq /s3b_rd_buf_tb/ddr_raddr /s3b_rd_buf_tb/ddr_rdone /s3b_rd_buf_tb/rd_fsync /s3b_rd_buf_tb/ddr_rstn; run -all; quit -code 0',
        '-l','simulation.log') 'console.log'
    $text = Get-Content -LiteralPath (Join-Path $run 'simulation.log') -Raw
    if ($text -match '\*\* (Error|Fatal):') { throw 'Simulator reported Error/Fatal.' }
    $match = [regex]::Match($text,
        'S3B_RESULT frames=(\d+) requests=(\d+) completions=(\d+) beats=(\d+) pixels=(\d+) errors=(\d+)')
    if (-not $match.Success) { throw 'Missing completed regression result.' }
    $keys = @('Frames','Requests','Completions','ReturnedBeats','Pixels','PixelErrors')
    for ($i = 0; $i -lt $keys.Count; $i++) { $result[$keys[$i]] = [int]$match.Groups[$i+1].Value }
    if ($result.Frames -ne 3 -or $result.Requests -ne 2160 -or
        $result.Completions -ne 2160 -or $result.ReturnedBeats -ne 172800 -or
        $result.Pixels -ne 2764800 -or $result.PixelErrors -ne 0) {
        throw 'Unexpected coverage totals.'
    }
    $result.Verdict = 'PASS'
} catch {
    $result.Error = $_.Exception.Message
} finally {
    Pop-Location
    $after = Hashes
    Save-Json 'inputs_after.json' $after
    $result.InputsUnchanged = @(Compare-Object $before $after -Property Path,SHA256).Count -eq 0
    if (-not $result.InputsUnchanged) { $result.Verdict = 'INVALID_INPUT_CHANGED' }
    Save-Json 'commands.json' @($commands.ToArray())
    Save-Json 'result.json' $result
    Save-Json 'evidence_manifest.json' @(Get-ChildItem -LiteralPath $run -File |
        Where-Object Name -ne 'evidence_manifest.json' | ForEach-Object {
            [pscustomobject]@{ Path=$_.FullName; Size=$_.Length
                SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
        })
}
$result | ConvertTo-Json -Depth 6
if ($result.Verdict -ne 'PASS') { exit 1 }
