param(
    [string]$OutputParent = 'E:\FPGA drive\tmp\s5_diag',
    [string]$ModelSim = 'D:\PDS\Modelsim\win64',
    [string]$Python = 'C:\Users\19511\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$stamp = (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$run = [IO.Path]::GetFullPath((Join-Path $OutputParent $stamp))
$allowed = [IO.Path]::GetFullPath((Join-Path (Split-Path $repo -Parent) 'tmp'))
if (-not $run.StartsWith($allowed + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Output must remain under workspace tmp.'
}
if (Test-Path -LiteralPath $run) { throw 'Output already exists.' }
$inputs = @(
    (Join-Path $repo 'source\rtl\net_diag\mes50hp_diag.v'),
    (Join-Path $PSScriptRoot 'diag_tb.sv'),
    (Join-Path $PSScriptRoot 'test_link.py'),
    (Join-Path $repo 'host\mes50hp_link\link.py'),
    $PSCommandPath
)
function Hashes {
    @($inputs | ForEach-Object { [pscustomobject]@{
        Path=$_; SHA256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash
    } })
}
foreach ($name in @('vlib.exe','vlog.exe','vsim.exe','vmap.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $ModelSim $name))) { throw "Missing $name" }
}
if (-not (Test-Path -LiteralPath $Python)) { throw 'Python executable missing.' }
[IO.Directory]::CreateDirectory($run) | Out-Null
$before = Hashes
$commands = [Collections.Generic.List[object]]::new()
$result = [ordered]@{ Verdict='ERROR'; RunDirectory=$run; Error=$null;
    PhysicalEthernet=$false; FullMACSimulation=$false; BoardTest=$false; PDSBuild=$false }
function Save-Json($Name,$Value) {
    ConvertTo-Json -InputObject $Value -Depth 8 | Set-Content -LiteralPath (Join-Path $run $Name) -Encoding utf8
}
function Invoke-Logged([string]$Tool,[string[]]$Arguments,[string]$Log) {
    & $Tool @Arguments *> (Join-Path $run $Log)
    $code = $LASTEXITCODE
    $commands.Add([pscustomobject]@{ Tool=$Tool; Arguments=$Arguments; ExitCode=$code; Log=$Log })
    if ($code -ne 0) { throw "$Tool exited $code; see $Log" }
}
Save-Json 'inputs_before.json' $before
Push-Location $run
try {
    $env:PYTHONDONTWRITEBYTECODE = '1'
    Invoke-Logged $Python @((Join-Path $PSScriptRoot 'test_link.py'),'-v') 'host_tests.log'
    Invoke-Logged $Python @((Join-Path $PSScriptRoot 'test_link.py'),'--vectors',(Join-Path $run 'vectors')) 'vectors.log'
    Invoke-Logged (Join-Path $ModelSim 'vlog.exe') @('-version') 'version.log'
    Invoke-Logged (Join-Path $ModelSim 'vlib.exe') @('work') 'vlib.log'
    Invoke-Logged (Join-Path $ModelSim 'vmap.exe') @('-c') 'vmap_config.log'
    Invoke-Logged (Join-Path $ModelSim 'vmap.exe') @('work',(Join-Path $run 'work')) 'vmap.log'
    Invoke-Logged (Join-Path $ModelSim 'vlog.exe') @('-sv','-work','work',$inputs[0],$inputs[1]) 'compile.log'
    Invoke-Logged (Join-Path $ModelSim 'vsim.exe') @('-c','-t','1ps','-lib','work','s5_diag_tb',
        '-do','onerror {quit -code 2}; run -all; quit -code 0',
        '-l',(Join-Path $run 'simulation.log')) 'simulation_console.log'
    $text = Get-Content -LiteralPath (Join-Path $run 'simulation.log') -Raw
    if ($text -match '\*\* (Error|Fatal):') { throw 'RTL simulation Error/Fatal.' }
    $match = [regex]::Match($text,'S5_RESULT cases=(\d+) errors=0')
    if (-not $match.Success -or [int]$match.Groups[1].Value -lt 280) { throw 'RTL checks did not complete.' }
    $result.RTLCases = [int]$match.Groups[1].Value
    $result.HostTests = 9
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
}
$result | ConvertTo-Json -Depth 8
if ($result.Verdict -ne 'PASS') { exit 1 }
