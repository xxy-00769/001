param(
    [string]$OutputParent = 'E:\FPGA drive\tmp\s3a_wr_completion',
    [string]$ModelSim = 'D:\PDS\Modelsim\win64'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$rtl = Join-Path $repo 'source\rtl\wr_cmd_trans.v'
$tb = Join-Path $PSScriptRoot 'regression_tb.sv'
$stamp = (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$run = [IO.Path]::GetFullPath((Join-Path $OutputParent $stamp))
if (Test-Path -LiteralPath $run) { throw 'Output directory already exists.' }
$allowedParent = [IO.Path]::GetFullPath((Join-Path (Split-Path $repo -Parent) 'tmp'))
if (-not $run.StartsWith($allowedParent + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Regression outputs must remain under the workspace tmp directory.'
}
foreach ($name in @('vlib.exe', 'vlog.exe', 'vsim.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $ModelSim $name))) {
        throw "Missing ModelSim executable: $name"
    }
}
[IO.Directory]::CreateDirectory($run) | Out-Null
$inputs = @($rtl, $tb, $PSCommandPath)
$before = @($inputs | ForEach-Object { Get-FileHash -LiteralPath $_ -Algorithm SHA256 })
$before | Select-Object Path,Hash | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'inputs.json') -Encoding utf8
$commands = [Collections.Generic.List[object]]::new()
$result = [ordered]@{
    Stage = 'S3a'; TestLevel = 'RTL simulation'; RunDirectory = $run
    Synthesis = $false; BoardTest = $false; Verdict = 'ERROR'; Error = $null
}
function Invoke-Tool([string]$Name, [string[]]$Arguments, [string]$Log) {
    $tool = Join-Path $ModelSim $Name
    & $tool @Arguments *> (Join-Path $run $Log)
    $code = $LASTEXITCODE
    $commands.Add([pscustomobject]@{
        Tool = $tool; Arguments = $Arguments; WorkingDirectory = $run
        ExitCode = $code; Log = $Log
    })
    if ($code -ne 0) { throw "$Name exited $code; see $Log" }
}
Push-Location $run
try {
    Invoke-Tool 'vlog.exe' @('-version') 'version.log'
    Invoke-Tool 'vlib.exe' @('work') 'library.log'
    Invoke-Tool 'vlog.exe' @('-sv', '-work', 'work', $rtl, $tb) 'compile.log'
    Invoke-Tool 'vsim.exe' @('-c', '-t', '1ps', '-lib', 'work',
        's3a_wr_completion_tb', '-do',
        'onerror {quit -code 2}; run -all; quit -code 0',
        '-l', 'simulation.log') 'console.log'
    $text = Get-Content -LiteralPath (Join-Path $run 'simulation.log') -Raw
    if ($text -match '\*\* (Error|Fatal):') { throw 'Simulation reported Error/Fatal.' }
    $match = [regex]::Match($text,
        'S3A_RESULT cases=(\d+) commands=(\d+) returns=(\d+) completions=(\d+) checks=(\d+) errors=0')
    if (-not $match.Success) { throw 'Missing completed regression result.' }
    $keys = @('Cases', 'Commands', 'Returns', 'Completions', 'Checks')
    for ($i = 0; $i -lt $keys.Count; $i++) { $result[$keys[$i]] = [int]$match.Groups[$i + 1].Value }
    if ($result.Cases -ne 16 -or $result.Commands -ne 16 -or
        $result.Returns -ne 1092 -or $result.Completions -ne 13) {
        throw 'Unexpected regression coverage totals.'
    }
    $result.Verdict = 'PASS'
} catch {
    $result.Error = $_.Exception.Message
} finally {
    Pop-Location
    $after = @($inputs | ForEach-Object { Get-FileHash -LiteralPath $_ -Algorithm SHA256 })
    $result.InputsUnchanged = @(Compare-Object $before $after -Property Path,Hash).Count -eq 0
    if (-not $result.InputsUnchanged) { $result.Verdict = 'INVALID_INPUT_CHANGED' }
    ConvertTo-Json -InputObject @($commands.ToArray()) -Depth 6 |
        Set-Content -LiteralPath (Join-Path $run 'commands.json') -Encoding utf8
    $result | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $run 'result.json') -Encoding utf8
}
$result | ConvertTo-Json -Depth 6
if ($result.Verdict -ne 'PASS') { exit 1 }
