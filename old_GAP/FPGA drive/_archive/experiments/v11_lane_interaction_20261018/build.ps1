$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$python = Join-Path $project '.venv-road-model/Scripts/python.exe'
$pds = 'D:/PDS/PDS_2022.2-SP6.1/bin/pds_shell.exe'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$run = Join-Path $PSScriptRoot "builds/${stamp}_rule_test"
& $python -X utf8 "$PSScriptRoot/build.py" prepare --run $run
if ($LASTEXITCODE -ne 0) { throw 'Isolated build preparation failed' }
Push-Location $run
try {
    & $pds -file impl.tcl -continue *> build.log
    $toolExit = $LASTEXITCODE
    & $python -X utf8 "$PSScriptRoot/build.py" check --run $run --tool-exit $toolExit
    if ($LASTEXITCODE -ne 0) { throw "Build not accepted; evidence kept: $run" }
} finally {
    Pop-Location
}
Write-Output "Isolated build evidence: $run"
