$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$python = Join-Path $root '.venv-road-model/Scripts/python.exe'
$vivado = 'D:\Xilinx\Vivado\2018.3\bin'
Push-Location $PSScriptRoot
try {
    & $python -X utf8 -m unittest -v test_reference.py
    if ($LASTEXITCODE -ne 0) { throw 'Reference unit tests failed' }
    & $python -X utf8 generate.py
    if ($LASTEXITCODE -ne 0) { throw 'Model/reference export failed' }
    & "$vivado\xvlog.bat" --sv ../source/layer0_params.v ../source/layer0_tile.v layer0_tb.v
    if ($LASTEXITCODE -ne 0) { throw 'RTL compilation failed' }
    & "$vivado\xelab.bat" layer0_tb --O3 -s layer0_tile_test
    if ($LASTEXITCODE -ne 0) { throw 'Elaboration failed' }
    & "$vivado\xsim.bat" layer0_tile_test -runall -log layer0.log
    if ($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
    $log = Get-Content -Raw -LiteralPath 'layer0.log'
    if ($log -notmatch 'PASS: 576 jobs, 589824 bit-exact outputs' -or $log -match 'Fatal:|\$fatal|ERROR:') {
        throw 'Missing clean simulation pass'
    }
} finally {
    Pop-Location
}
