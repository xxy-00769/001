$ErrorActionPreference = 'Stop'
$project = (Resolve-Path "$PSScriptRoot/../..").Path
$python = Join-Path $project '.venv-road-model/Scripts/python.exe'
$modelsim = 'D:/PDS/Modelsim/win64'
$run = Join-Path $PSScriptRoot ("runs/" + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
& $python -X utf8 "$PSScriptRoot/prepare.py" prepare --run $run
if ($LASTEXITCODE -ne 0) { throw 'Preparation failed' }
Push-Location $run
try {
    & "$modelsim/vlib.exe" work *> library.log
    if ($LASTEXITCODE -ne 0) { throw 'Library creation failed' }
    $names = @('img_proc','lane_detect','lane_geometry','zebra_detect','zebra_overlay',
        'adas_overlay','lane_button_events','lane_change_control','lane_change_overlay',
        'lane_local_ui','lane_snapshot_cdc','lane_rule_test_source','hdmi_ddr_ov5640_top')
    $sources = @($names | ForEach-Object { "source/rtl/$_.v" })
    & "$modelsim/vlog.exe" -sv -work work @sources "$PSScriptRoot/tests/camera_pipeline_tb.sv" "$project/experiments/v11_lane_interaction_20261018/tests/cdc_tb.sv" *> compile.log
    if ($LASTEXITCODE -ne 0) { throw "Compile failed: $run" }
    foreach ($name in @('camera_pipeline','cdc')) {
        & "$modelsim/vsim.exe" -c -novopt -t 1ps -suppress 12110 -lib work "${name}_tb" -do 'run -all; quit -code 0' -l "$name.simulation.log" *> "$name.console.log"
        $code = $LASTEXITCODE
        $log = Get-Content -LiteralPath "$name.simulation.log" -Raw
        if ($code -ne 0 -or $log -notmatch "PASS $($name):" -or $log -match '\*\* (Error|Fatal):') {
            throw "Simulation failed: $run/$name.simulation.log"
        }
        Write-Output ($log -split "`n" | Where-Object { $_ -match "PASS $($name):" })
    }
    & $python -X utf8 "$PSScriptRoot/prepare.py" verify --run $run
    if ($LASTEXITCODE -ne 0) { throw 'Evidence verification failed' }
} finally {
    Pop-Location
}
Write-Output "Camera-candidate test evidence: $run"
