$ErrorActionPreference='Stop'
$project=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$experiment=Split-Path $PSScriptRoot
$modelsim='D:/PDS/Modelsim/win64'
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$run=Join-Path $experiment "runs/${stamp}_control"
$null=New-Item -ItemType Directory -Path $run
& "$project/.venv-road-model/Scripts/python.exe" -X utf8 "$PSScriptRoot/audit.py" --capture $run
if($LASTEXITCODE -ne 0) { throw 'Audit failed' }
Push-Location $run
try {
    foreach($variant in @('original','candidate')) {
        & "$modelsim/vlib.exe" $variant *> "$variant.library.log"
        $source=if($variant -eq 'original') {
            Join-Path $project 'source/rtl/wr_cmd_trans.v'
        } else { Join-Path $experiment 'source/wr_cmd_trans.v' }
        & "$modelsim/vlog.exe" -sv -work $variant $source "$PSScriptRoot/control_tb.sv" *> "$variant.compile.log"
        if($LASTEXITCODE -ne 0) { throw 'Compile failed' }
        & "$modelsim/vsim.exe" -c -novopt -t 1ps -suppress 12110 -lib $variant control_tb -do 'run -all; quit -code 0' -l "$variant.simulation.log" *> "$variant.console.log"
        if($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
        Get-Content "$variant.simulation.log" | Where-Object {$_ -match 'CONTROL_RESULT|PASS:|REJECT:'}
    }
    $old=Get-Content -Raw original.simulation.log
    $new=Get-Content -Raw candidate.simulation.log
    if(!$old.Contains('REJECT: premature') -or !$new.Contains('PASS: final-return') -or $new -match '\*\* (Error|Fatal):') {
        throw 'Control regression missing expected original failure/candidate pass'
    }
    & "$project/.venv-road-model/Scripts/python.exe" -X utf8 "$PSScriptRoot/audit.py" --check-inputs $run
    if($LASTEXITCODE -ne 0) { throw 'Input stability failed' }
} finally { Pop-Location }
Write-Output "Control evidence: $run"
