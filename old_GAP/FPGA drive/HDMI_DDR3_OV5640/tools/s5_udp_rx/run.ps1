param(
    [string]$OutputParent = 'E:\FPGA drive\tmp\s5_udp_rx',
    [string]$ModelSim = 'D:\PDS\Modelsim\win64',
    [string]$Python = 'C:\Users\19511\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$run = [IO.Path]::GetFullPath((Join-Path $OutputParent (
    (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,8))))
$allowed = [IO.Path]::GetFullPath((Join-Path (Split-Path $repo -Parent) 'tmp'))
if (-not $run.StartsWith($allowed + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Output outside workspace tmp.' }
if (Test-Path -LiteralPath $run) { throw 'Output already exists.' }
$inputs = @((Join-Path $repo 'source\rtl\net_diag\mes50hp_udp_rx.v'),
    (Join-Path $PSScriptRoot 'udp_rx_tb.sv'), (Join-Path $PSScriptRoot 'generate_vectors.py'),
    (Join-Path $repo 'source\rtl\net_diag\mes50hp_diag.v'), $PSCommandPath)
function Hashes {
    @($inputs | ForEach-Object {
        [pscustomobject]@{Path=$_; SHA256=(Get-FileHash -LiteralPath $_).Hash}
    })
}
foreach ($name in @('vlib.exe','vlog.exe','vmap.exe','vsim.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $ModelSim $name))) { throw "Missing $name" }
}
[IO.Directory]::CreateDirectory($run) | Out-Null
$before = Hashes
$commands = [Collections.Generic.List[object]]::new()
function Save-Json($Name,$Value) {
    ConvertTo-Json -InputObject $Value -Depth 8 | Set-Content -LiteralPath (Join-Path $run $Name) -Encoding utf8
}
function Invoke-Logged([string]$Tool,[string[]]$Arguments,[string]$Log) {
    & $Tool @Arguments *> (Join-Path $run $Log)
    $code = $LASTEXITCODE
    $commands.Add([pscustomobject]@{Tool=$Tool;Arguments=$Arguments;ExitCode=$code;Log=$Log})
    if ($code -ne 0) { throw "$Tool exited $code; see $Log" }
}
$result = [ordered]@{Verdict='ERROR';Error=$null;RunDirectory=$run;
    PhysicalEthernet=$false; BoardTest=$false; Synthesis=$false; MainIntegration=$false}
Save-Json 'inputs_before.json' $before
Push-Location $run
try {
    Invoke-Logged $Python @($inputs[2], (Join-Path $run 'vectors')) 'vectors.log'
    Invoke-Logged (Join-Path $ModelSim 'vlog.exe') @('-version') 'version.log'
    Invoke-Logged (Join-Path $ModelSim 'vlib.exe') @('work') 'vlib.log'
    Invoke-Logged (Join-Path $ModelSim 'vmap.exe') @('-c') 'vmap_config.log'
    Invoke-Logged (Join-Path $ModelSim 'vmap.exe') @('work',(Join-Path $run 'work')) 'vmap.log'
    Invoke-Logged (Join-Path $ModelSim 'vlog.exe') @('-sv','-work','work',
        ('+incdir+' + (Join-Path $run 'vectors')), $inputs[0], $inputs[1], $inputs[3]) 'compile.log'
    Invoke-Logged (Join-Path $ModelSim 'vsim.exe') @('-c','-t','1ps','-lib','work','s5_udp_rx_tb',
        '-do','onerror {quit -code 2}; run -all; quit -code 0',
        '-l',(Join-Path $run 'simulation.log')) 'simulation_console.log'
    $text = Get-Content -LiteralPath (Join-Path $run 'simulation.log') -Raw
    if ($text -match '\*\* (Error|Fatal):') { throw 'RTL simulation Error/Fatal.' }
    $match = [regex]::Match($text,'S5_RX_RESULT cases=(\d+) errors=0')
    if (-not $match.Success -or [int]$match.Groups[1].Value -ne 42) { throw 'Directed checks incomplete.' }
    $result.RTLCases = [int]$match.Groups[1].Value
    $result.Verdict = 'PASS'
} catch {
    $result.Error = $_.Exception.Message
} finally {
    Pop-Location
    $after = Hashes
    Save-Json 'inputs_after.json' $after
    $result.InputsUnchanged = @(Compare-Object $before $after -Property Path,SHA256).Count -eq 0
    if (-not $result.InputsUnchanged) { $result.Verdict='INVALID_INPUT_CHANGED' }
    Save-Json 'commands.json' @($commands.ToArray())
    Save-Json 'result.json' $result
}
$result | ConvertTo-Json -Depth 8
if ($result.Verdict -ne 'PASS') { exit 1 }
