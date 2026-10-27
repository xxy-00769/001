$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$python = Join-Path $root '.venv-road-seg/Scripts/python.exe'
$vivado = 'D:\Xilinx\Vivado\2018.3\bin'
Push-Location $PSScriptRoot
try {
    & $python -X utf8 fixtures.py
    if ($LASTEXITCODE -ne 0) { throw 'Reference generation failed' }
    & "$vivado\xvlog.bat" --sv ../source/road_thumbnail.v ../source/road_input_buffer.v road_input_tb.v
    if ($LASTEXITCODE -ne 0) { throw 'RTL compile failed' }
    & "$vivado\xelab.bat" road_input_tb --O3 -s road_input_small
    if ($LASTEXITCODE -ne 0) { throw 'Small elaboration failed' }
    cmd /d /c ('{0}\xelab.bat road_input_tb --O3 -generic_top "W=1280" -generic_top "H=720" -s road_input_full' -f $vivado)
    if ($LASTEXITCODE -ne 0) { throw 'Full elaboration failed' }
    foreach ($case in @('small', 'extreme', 'road', 'shelf')) {
        $snapshot = if ($case -in @('small', 'extreme')) { 'road_input_small' } else { 'road_input_full' }
        cmd /d /c ('{0}\xsim.bat {1} -runall -testplusarg "A=output/{2}_0.hex" -testplusarg "B=output/{2}_1.hex" -log {2}.log' -f $vivado, $snapshot, $case)
        if ($LASTEXITCODE -ne 0) { throw "Simulation failed: $case" }
        $log = Get-Content -Raw -LiteralPath "$case.log"
        if ($log -notmatch 'PASS: .*protected snapshots' -or $log -match 'Fatal:|\$fatal|ERROR:') {
            throw "Missing clean simulation pass: $case"
        }
    }
} finally {
    Pop-Location
}
