param([string]$ReuseTestsFrom = '')
$ErrorActionPreference = 'Stop'
$experiment = Split-Path $PSScriptRoot
$project = (Resolve-Path (Join-Path $experiment '../..')).Path
$modelsim = 'D:/PDS/Modelsim/win64'
$python = Join-Path $project '.venv-road-model/Scripts/python.exe'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$run = Join-Path $experiment "runs/$stamp"
$null = New-Item -ItemType Directory -Path $run
$prepareArgs = @('--run', $run)
if ($ReuseTestsFrom) { $prepareArgs += @('--reuse-tests-from', $ReuseTestsFrom) }
& $python -X utf8 "$PSScriptRoot/prepare.py" @prepareArgs
if ($LASTEXITCODE -ne 0) { throw 'Preparation failed' }
Push-Location $run
try {
    & "$modelsim/vlib.exe" work *> library.log
    if ($LASTEXITCODE -ne 0) { throw 'Library creation failed' }
    $sources = @(Get-ChildItem "$experiment/source" -Filter '*.v' | ForEach-Object FullName)
    $benches = @(Get-ChildItem $PSScriptRoot -Filter '*_tb.sv' | ForEach-Object FullName)
    & "$modelsim/vlog.exe" -sv -work work @sources @benches *> compile.log
    if ($LASTEXITCODE -ne 0) { throw "Compile failed: $run/compile.log" }
    $testNames = if ($ReuseTestsFrom) { @() } else {
        @('buttons','control','cdc','rule_source','overlay','local_ui')
    }
    foreach ($name in $testNames) {
        & "$modelsim/vsim.exe" -c -novopt -t 1ps -suppress 12110 -lib work "${name}_tb" -do 'run -all; quit -code 0' -l "$name.simulation.log" *> "$name.console.log"
        $exitCode = $LASTEXITCODE
        $log = Get-Content -LiteralPath "$name.simulation.log" -Raw
        if ($exitCode -ne 0 -or $log -notmatch "PASS $($name):" -or $log -match '\*\* (Error|Fatal):') {
            throw "Test failed: $run/$name.simulation.log"
        }
        Write-Output ($log -split "`n" | Where-Object { $_ -match "PASS $($name):" })
    }
    # Syntax check only: unresolved vendor cores are NOT elaborated or stubbed.
    & "$modelsim/vlog.exe" -sv -work work generated/hdmi_ddr_ov5640_top.v *> top.syntax.log
    if ($LASTEXITCODE -ne 0) { throw 'Generated top syntax failed' }
    & $python -X utf8 "$PSScriptRoot/prepare.py" --run $run --verify
    if ($LASTEXITCODE -ne 0) { throw 'Evidence verification failed' }
} finally {
    Pop-Location
}
Write-Output "Evidence: $run"
