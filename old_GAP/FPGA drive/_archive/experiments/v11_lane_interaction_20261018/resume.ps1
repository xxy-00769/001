param(
    [Parameter(Mandatory=$true)][string]$PreviousBuild
)
$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$python = Join-Path $project '.venv-road-model/Scripts/python.exe'
$pds = 'D:/PDS/PDS_2022.2-SP6.1/bin/pds_shell.exe'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$run = Join-Path $PSScriptRoot "builds/${stamp}_resume_pnr"
& $python -X utf8 "$PSScriptRoot/build.py" resume --run $run --from-run $PreviousBuild
if ($LASTEXITCODE -ne 0) { throw 'Checkpoint validation/copy failed' }
Push-Location $run
try {
    $toolExit = 0
    # Invoke the single-action backend, not the dependency dispatcher.
    foreach ($action in @('place_route')) {
        & $pds -action $action -project_file "$run/impl.pds" *> "$action.log"
        $toolExit = $LASTEXITCODE
        Get-Content -LiteralPath "$action.log" | Add-Content -LiteralPath build.log
        $log = Get-Content -LiteralPath "$action.log" -Raw
        if ($toolExit -ne 0 -or $log -match '(?m)^\s*E:\s|(?:ERROR:|Error:|FATAL:|Fatal:)') {
            $toolExit = 1
            break
        }
    }
    if ($toolExit -ne 0) { throw "PNR failed; evidence kept: $run" }
    & $python -X utf8 "$PSScriptRoot/build.py" collect-pnr --run $run
    if ($LASTEXITCODE -ne 0) { throw "PNR output collection failed: $run" }
    foreach ($script in @('timing_only', 'bitstream_only')) {
        & $pds -file "$script.tcl" *> "$script.log"
        $toolExit = $LASTEXITCODE
        Get-Content -LiteralPath "$script.log" | Add-Content -LiteralPath build.log
        $log = Get-Content -LiteralPath "$script.log" -Raw
        if ($toolExit -ne 0 -or $log -match '(?m)^\s*E:\s|(?:ERROR:|Error:|FATAL:|Fatal:)') {
            $toolExit = 1
            break
        }
        if ($script -eq 'timing_only') {
            $report = Join-Path $run 'report_timing/hdmi_ddr_ov5640_top.rtr'
            if (-not (Test-Path -LiteralPath $report) -or
                -not ((Get-Content -LiteralPath $report -Raw).Contains('Design Summary : All Constraints Met.'))) {
                $toolExit = 1
                break
            }
        }
    }
    & $python -X utf8 "$PSScriptRoot/build.py" check --run $run --tool-exit $toolExit
    if ($LASTEXITCODE -ne 0) { throw "Resume not accepted; evidence kept: $run" }
} finally {
    Pop-Location
}
Write-Output "Resumed build evidence: $run"
