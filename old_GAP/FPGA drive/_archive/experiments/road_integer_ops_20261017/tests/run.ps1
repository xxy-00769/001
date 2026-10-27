param([switch]$SkipGenerate)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$python = Join-Path $root '.venv-road-model/Scripts/python.exe'
$vivado = 'D:/Xilinx/Vivado/2018.3/bin'
Push-Location $PSScriptRoot
try {
    & $python -X utf8 -m unittest -v test_reference.py
    if ($LASTEXITCODE -ne 0) { throw 'Reference tests failed' }
    if (!$SkipGenerate) {
        & $python -X utf8 generate.py
        if ($LASTEXITCODE -ne 0) { throw 'Reference generation failed' }
    }
    $inputs = @{}
    foreach ($file in @('../source/conv_tile.v','../source/residual_requant.v','conv_tb.v','residual_tb.v',
        'output/cases.vh','output/residual_params.vh','output/inputs.hex','output/weights.hex',
        'output/coefficients.hex','output/expected.hex','output/descriptors.txt','output/residual_expected.hex')) {
        $inputs[$file] = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    }
    & "$vivado/xvlog.bat" --sv ../source/conv_tile.v ../source/residual_requant.v conv_tb.v residual_tb.v
    if ($LASTEXITCODE -ne 0) { throw 'RTL compile failed' }
    foreach ($name in @('conv', 'residual')) {
        & "$vivado/xelab.bat" "${name}_tb" --O3 -s "road_ops_$name"
        if ($LASTEXITCODE -ne 0) { throw "$name elaboration failed" }
        & "$vivado/xsim.bat" "road_ops_$name" -runall -log "$name.log"
        if ($LASTEXITCODE -ne 0) { throw "$name simulation failed" }
        $log = Get-Content -Raw -LiteralPath "$name.log"
        if ($log -notmatch "PASS: $name " -or $log -match 'Fatal:|\$fatal|ERROR:') { throw "Missing clean $name pass" }
    }
    foreach ($file in $inputs.Keys) {
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $inputs[$file]) { throw "Source changed during simulation: $file" }
    }
    $inputs | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath 'output/rtl_build_inputs.json'
} finally { Pop-Location }
