param(
    [Parameter(Mandatory=$true)][string]$SimulationResult,
    [string]$OutputParent = 'E:\FPGA drive\tmp\s5_diag_synthesis',
    [string]$Pds = 'D:\PDS\PDS_2022.2-SP6.1\bin\pds_shell.exe'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$sim = Get-Content -LiteralPath $SimulationResult -Raw | ConvertFrom-Json
if ($sim.Verdict -ne 'PASS' -or -not $sim.InputsUnchanged) { throw 'RTL PASS evidence required.' }
$simInputs = @(Get-Content -LiteralPath (Join-Path (Split-Path $SimulationResult -Parent) 'inputs_after.json') -Raw | ConvertFrom-Json)
foreach ($item in $simInputs) {
    if ((Get-FileHash -LiteralPath $item.Path -Algorithm SHA256).Hash -ne $item.SHA256) {
        throw "Simulation input changed: $($item.Path)"
    }
}
$stamp = (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$run = [IO.Path]::GetFullPath((Join-Path $OutputParent $stamp))
$allowed = [IO.Path]::GetFullPath((Join-Path (Split-Path $repo -Parent) 'tmp'))
if (-not $run.StartsWith($allowed + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Output outside workspace tmp.' }
if (Test-Path -LiteralPath $run) { throw 'Output already exists.' }
if (-not (Test-Path -LiteralPath $Pds)) { throw 'PDS missing.' }
[IO.Directory]::CreateDirectory($run) | Out-Null
$rtl = Join-Path $repo 'source\rtl\net_diag\mes50hp_diag.v'
$recipe = Join-Path $PSScriptRoot 'synthesize.tcl'
$protected = @('source\rtl\hdmi_ddr_ov5640_top.v','source\rtl\img_proc.v',
    'source\rtl\wr_cmd_trans.v','source\rtl\rd_buf.v','flow.tcl',
    'hdmi_ddr_ov5640_top.fdc','HDMI_DDR3_OV5640.pds') | ForEach-Object { Join-Path $repo $_ }
$manifest = @(@($rtl,$recipe,$PSCommandPath) + $protected | ForEach-Object {
    [pscustomobject]@{Path=$_; SHA256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}
})
function Save-Json($Name,$Value) {
    ConvertTo-Json -InputObject $Value -Depth 8 | Set-Content -LiteralPath (Join-Path $run $Name) -Encoding utf8
}
Save-Json 'inputs_before.json' $manifest
Copy-Item -LiteralPath $rtl -Destination (Join-Path $run 'mes50hp_diag.v')
Copy-Item -LiteralPath $recipe -Destination (Join-Path $run 'build.tcl')
Save-Json 'recipe.json' ([ordered]@{Top='mes50hp_diag'; Tool=$Pds;
    Arguments=@('-file','build.tcl','-continue'); Simulation=[IO.Path]::GetFullPath($SimulationResult);
    StartedUtc=[DateTime]::UtcNow.ToString('o'); Scope='Application only; no main project integration'})
$result = [ordered]@{Verdict='ERROR'; Error=$null; RunDirectory=$run;
    ProcessExitCode=$null; Compile=$false; Synthesis=$false; PlaceRoute=$false;
    Timing=$false; Bitstream=$false; BoardTest=$false; PhysicalEthernet=$false}
Write-Output "PDS application synthesis: $run"
Push-Location $run
try {
    & $Pds -file build.tcl -continue *> (Join-Path $run 'pds_console.log')
    $result.ProcessExitCode = $LASTEXITCODE
    if ($LASTEXITCODE -ne 0) { throw "PDS exited $LASTEXITCODE" }
    $text = Get-Content -LiteralPath (Join-Path $run 'pds_console.log') -Raw
    if ($text -match '(?im)^\s*(?:E:|\*\* (?:Error|Fatal):)|Program Error') { throw 'PDS reported an error.' }
    $result.Compile = Test-Path -LiteralPath (Join-Path $run 'compile\mes50hp_diag_comp.adf')
    $result.Synthesis = Test-Path -LiteralPath (Join-Path $run 'synthesize\mes50hp_diag_syn.adf')
    if (-not $result.Compile -or -not $result.Synthesis) { throw 'Expected stage artifact missing.' }
    if (Test-Path -LiteralPath (Join-Path $run 'generate_bitstream')) { throw 'Unexpected bitstream stage.' }
    $result.Verdict = 'PASS'
} catch {
    $result.Error = $_.Exception.Message
} finally {
    Pop-Location
    $after = @($manifest | ForEach-Object {
        [pscustomobject]@{Path=$_.Path; SHA256=(Get-FileHash -LiteralPath $_.Path -Algorithm SHA256).Hash}
    })
    Save-Json 'inputs_after.json' $after
    $result.InputsUnchanged = @(Compare-Object $manifest $after -Property Path,SHA256).Count -eq 0
    $result.CopiedRTLUnchanged = (Get-FileHash -LiteralPath (Join-Path $run 'mes50hp_diag.v')).Hash -eq (Get-FileHash -LiteralPath $rtl).Hash
    if (-not $result.InputsUnchanged -or -not $result.CopiedRTLUnchanged) { $result.Verdict='INVALID_INPUT_CHANGED' }
    Save-Json 'result.json' $result
}
$result | ConvertTo-Json -Depth 8
if ($result.Verdict -ne 'PASS') { exit 1 }
